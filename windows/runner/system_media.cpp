#include "system_media.h"

#include <roapi.h>
#include <shcore.h>
#include <shlwapi.h>
#include <systemmediatransportcontrolsinterop.h>
#include <windows.storage.streams.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HStringReference;

namespace media = ABI::Windows::Media;
namespace streams = ABI::Windows::Storage::Streams;
using ABI::Windows::Foundation::ITypedEventHandler;
using ABI::Windows::Foundation::TimeSpan;

namespace {

// WinRT cuenta el tiempo en unidades de 100 ns; la Web API, en milisegundos.
TimeSpan DesdeMs(int64_t ms) {
  TimeSpan t = {};
  t.Duration = ms * 10000;
  return t;
}

// La carátula, como fuente que el panel del sistema pueda leer.
//
// Se le da un `IStream` sobre el fichero que la app ya tiene en disco, envuelto
// para WinRT. La alternativa de manual —`StorageFile::GetFileFromPathAsync`—
// es asíncrona, y esperarla aquí bloquearía el hilo de la ventana; ir por
// `IStream` sale síncrono y sin hilos de por medio.
//
// ⚠️ Se abre con `STGM_SHARE_DENY_NONE`. Con el modo exclusivo, la poda de la
// caché de carátulas no podría borrar el fichero de la canción que esté
// sonando: fallaría con un error de uso compartido que no explicaría nada.
ComPtr<streams::IRandomAccessStreamReference> ReferenciaDeFichero(
    const std::wstring& ruta) {
  ComPtr<streams::IRandomAccessStreamReference> vacio;
  if (ruta.empty()) {
    return vacio;
  }

  ComPtr<IStream> fichero;
  if (FAILED(::SHCreateStreamOnFileEx(ruta.c_str(),
                                      STGM_READ | STGM_SHARE_DENY_NONE, 0,
                                      FALSE, nullptr, &fichero))) {
    return vacio;
  }

  ComPtr<streams::IRandomAccessStream> aleatorio;
  if (FAILED(::CreateRandomAccessStreamOverStream(fichero.Get(), BSOS_DEFAULT,
                                                  IID_PPV_ARGS(&aleatorio)))) {
    return vacio;
  }

  ComPtr<streams::IRandomAccessStreamReferenceStatics> estaticos;
  if (FAILED(::RoGetActivationFactory(
          HStringReference(
              RuntimeClass_Windows_Storage_Streams_RandomAccessStreamReference)
              .Get(),
          IID_PPV_ARGS(&estaticos)))) {
    return vacio;
  }

  ComPtr<streams::IRandomAccessStreamReference> referencia;
  if (FAILED(estaticos->CreateFromStream(aleatorio.Get(), &referencia))) {
    return vacio;
  }
  return referencia;
}

}  // namespace

SystemMediaControls::~SystemMediaControls() {
  Stop();
}

bool SystemMediaControls::Start(HWND window, UINT mensaje) {
  if (window == nullptr || smtc_ != nullptr) {
    return smtc_ != nullptr;
  }
  window_ = window;
  mensaje_ = mensaje;

  // Una app de escritorio no tiene "vista actual", así que los controles se
  // piden por ventana con la interfaz de interoperabilidad. La ruta de las apps
  // de la Store (`GetForCurrentView`) devuelve error aquí.
  ComPtr<ISystemMediaTransportControlsInterop> interop;
  if (FAILED(::RoGetActivationFactory(
          HStringReference(RuntimeClass_Windows_Media_SystemMediaTransportControls)
              .Get(),
          IID_PPV_ARGS(&interop)))) {
    return false;
  }
  if (FAILED(interop->GetForWindow(window_, IID_PPV_ARGS(&smtc_))) ||
      smtc_ == nullptr) {
    smtc_ = nullptr;
    return false;
  }

  smtc_->put_IsEnabled(TRUE);
  smtc_->put_IsPlayEnabled(TRUE);
  smtc_->put_IsPauseEnabled(TRUE);
  smtc_->put_IsNextEnabled(TRUE);
  smtc_->put_IsPreviousEnabled(TRUE);
  // No hay "parar" en esta app; el panel no debe enseñar un botón muerto.
  smtc_->put_IsStopEnabled(FALSE);
  // Hasta que Dart mande el primer estado no hay nada sonando.
  smtc_->put_PlaybackStatus(media::MediaPlaybackStatus_Closed);

  auto botones =
      Callback<ITypedEventHandler<media::SystemMediaTransportControls*,
                                  media::SystemMediaTransportControlsButtonPressedEventArgs*>>(
          [this](media::ISystemMediaTransportControls*,
                 media::ISystemMediaTransportControlsButtonPressedEventArgs*
                     args) -> HRESULT {
            media::SystemMediaTransportControlsButton boton = {};
            if (args == nullptr || FAILED(args->get_Button(&boton))) {
              return S_OK;
            }
            ComandoMultimedia comando = ComandoMultimedia::kPlayPause;
            switch (boton) {
              case media::SystemMediaTransportControlsButton_Play:
                comando = ComandoMultimedia::kPlay;
                break;
              case media::SystemMediaTransportControlsButton_Pause:
                comando = ComandoMultimedia::kPause;
                break;
              case media::SystemMediaTransportControlsButton_Stop:
                comando = ComandoMultimedia::kStop;
                break;
              case media::SystemMediaTransportControlsButton_Next:
                comando = ComandoMultimedia::kNext;
                break;
              case media::SystemMediaTransportControlsButton_Previous:
                comando = ComandoMultimedia::kPrevious;
                break;
              default:
                // Grabar, cambiar de canal, avanzar rápido: nada de eso existe
                // aquí, y tratarlos como un play/pausa sería peor que ignorarlos.
                return S_OK;
            }
            ::PostMessage(window_, mensaje_, static_cast<WPARAM>(comando), 0);
            return S_OK;
          });
  if (botones) {
    smtc_->add_ButtonPressed(botones.Get(), &token_boton_);
  }

  // La barra de progreso del panel y el poder arrastrarla son de la segunda
  // versión de la interfaz. En un Windows que no la tenga se pierde la barra y
  // el resto sigue funcionando, así que el fallo no se propaga.
  ComPtr<media::ISystemMediaTransportControls2> smtc2;
  if (SUCCEEDED(smtc_.As(&smtc2)) && smtc2 != nullptr) {
    auto salto =
        Callback<ITypedEventHandler<media::SystemMediaTransportControls*,
                                    media::PlaybackPositionChangeRequestedEventArgs*>>(
            [this](media::ISystemMediaTransportControls*,
                   media::IPlaybackPositionChangeRequestedEventArgs* args)
                -> HRESULT {
              TimeSpan destino = {};
              if (args == nullptr ||
                  FAILED(args->get_RequestedPlaybackPosition(&destino))) {
                return S_OK;
              }
              ::PostMessage(window_, mensaje_,
                            static_cast<WPARAM>(ComandoMultimedia::kSeek),
                            static_cast<LPARAM>(destino.Duration / 10000));
              return S_OK;
            });
    if (salto) {
      smtc2->add_PlaybackPositionChangeRequested(salto.Get(), &token_salto_);
    }
  }

  return true;
}

void SystemMediaControls::Stop() {
  if (smtc_ == nullptr) {
    return;
  }
  // Primero se quitan los avisos: los manejadores se quedaron con `this` y uno
  // que llegara tarde escribiría sobre un objeto ya destruido.
  if (token_boton_.value != 0) {
    smtc_->remove_ButtonPressed(token_boton_);
    token_boton_ = {};
  }
  if (token_salto_.value != 0) {
    ComPtr<media::ISystemMediaTransportControls2> smtc2;
    if (SUCCEEDED(smtc_.As(&smtc2)) && smtc2 != nullptr) {
      smtc2->remove_PlaybackPositionChangeRequested(token_salto_);
    }
    token_salto_ = {};
  }
  // Dejar de anunciarse: si no, el panel del sistema se queda con NeoFy y su
  // última canción después de cerrar la app.
  smtc_->put_PlaybackStatus(media::MediaPlaybackStatus_Closed);
  smtc_->put_IsEnabled(FALSE);
  smtc_ = nullptr;
  window_ = nullptr;
}

void SystemMediaControls::Update(const EstadoMultimedia& estado) {
  if (smtc_ == nullptr) {
    return;
  }

  // ⚠️ Sin canción es `Stopped`, no `Paused`. Con `Paused` el panel se queda
  // enseñando un reproductor parado que no tiene nada que reanudar.
  smtc_->put_PlaybackStatus(
      !estado.hay_cancion
          ? media::MediaPlaybackStatus_Stopped
          : (estado.sonando ? media::MediaPlaybackStatus_Playing
                            : media::MediaPlaybackStatus_Paused));
  smtc_->put_IsPlayEnabled(estado.hay_cancion ? TRUE : FALSE);
  smtc_->put_IsPauseEnabled(estado.hay_cancion ? TRUE : FALSE);
  smtc_->put_IsNextEnabled(estado.puede_saltar ? TRUE : FALSE);
  smtc_->put_IsPreviousEnabled(estado.puede_volver ? TRUE : FALSE);

  ComPtr<media::ISystemMediaTransportControlsDisplayUpdater> panel;
  if (FAILED(smtc_->get_DisplayUpdater(&panel)) || panel == nullptr) {
    return;
  }

  if (!estado.hay_cancion) {
    panel->ClearAll();
    panel->Update();
    return;
  }

  panel->put_Type(media::MediaPlaybackType_Music);

  ComPtr<media::IMusicDisplayProperties> musica;
  if (SUCCEEDED(panel->get_MusicProperties(&musica)) && musica != nullptr) {
    // ⚠️ Las variables no sobran. `HStringReference` no copia la cadena: se
    // queda apuntando a la que le pasan **y a su propia cabecera**, así que
    // devolverla desde una función auxiliar es justo lo que no hay que hacer.
    const HStringReference titulo(estado.titulo.c_str(),
                                  static_cast<UINT32>(estado.titulo.size()));
    const HStringReference artista(estado.artista.c_str(),
                                   static_cast<UINT32>(estado.artista.size()));
    musica->put_Title(titulo.Get());
    musica->put_Artist(artista.Get());
    // El álbum llegó en la segunda versión de la interfaz; sin ella se queda
    // sin álbum y ya está.
    ComPtr<media::IMusicDisplayProperties2> musica2;
    if (SUCCEEDED(musica.As(&musica2)) && musica2 != nullptr) {
      const HStringReference album(estado.album.c_str(),
                                   static_cast<UINT32>(estado.album.size()));
      musica2->put_AlbumTitle(album.Get());
    }
  }

  // Sin carátula se manda nullptr, que borra la anterior. Dejarla puesta haría
  // que el panel enseñara el disco de la canción de antes.
  panel->put_Thumbnail(ReferenciaDeFichero(estado.caratula).Get());

  // ⚠️ `Update()` es lo que publica todo lo anterior de golpe. Sin esta línea
  // se pueden poner título, artista y carátula y no cambia nada en pantalla.
  panel->Update();

  ActualizarLinea(estado);
}

void SystemMediaControls::ActualizarLinea(const EstadoMultimedia& estado) {
  ComPtr<media::ISystemMediaTransportControls2> smtc2;
  if (FAILED(smtc_.As(&smtc2)) || smtc2 == nullptr) {
    return;
  }

  ComPtr<IInspectable> creado;
  if (FAILED(::RoActivateInstance(
          HStringReference(
              RuntimeClass_Windows_Media_SystemMediaTransportControlsTimelineProperties)
              .Get(),
          &creado))) {
    return;
  }
  ComPtr<media::ISystemMediaTransportControlsTimelineProperties> linea;
  if (FAILED(creado.As(&linea)) || linea == nullptr) {
    return;
  }

  linea->put_StartTime(DesdeMs(0));
  linea->put_MinSeekTime(DesdeMs(0));
  linea->put_Position(DesdeMs(estado.posicion_ms));
  linea->put_MaxSeekTime(DesdeMs(estado.duracion_ms));
  linea->put_EndTime(DesdeMs(estado.duracion_ms));
  smtc2->UpdateTimelineProperties(linea.Get());
}
