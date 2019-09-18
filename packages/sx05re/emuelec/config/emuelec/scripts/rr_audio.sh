# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2018-present Frank Hartung (supervisedthinking@gmail.com)

# Set common paths and defaults
export PULSE_RUNTIME_PATH=/run/pulse
	RR_AUDIO_DEVICE="sysdefault:CARD=AMLM8AUDIO"
    RR_PA_UDEV="true"
    RR_PA_TSCHED="true"
    RR_AUDIO_VOLUME="100"
	

pulseaudio_sink_load() {

  if [ ${RR_AUDIO_BACKEND} = "PulseAudio" ];then
    if [ "${RR_PA_TSCHED}" = "false" ]; then
      TSCHED="tsched=0"
      echo "rr-config-script: PulseAudio will disable timer-based audio scheduling"
    else
      TSCHED="tsched=1"
      echo "rr-config-script: PulseAudio will enable timer-based audio scheduling"
    fi

    if [ ! -z "$(pactl list modules short | grep module-null-sink)" ];then
      if [ "${RR_PA_UDEV}" = "true" ]; then
        pactl load-module module-udev-detect $TSCHED > /dev/null
        pactl set-sink-volume "$(pactl info | grep 'Default Sink:' | cut -d ' ' -f 3)" ${RR_AUDIO_VOLUME}%
        if [ ! -z "$(pactl list modules short | grep module-alsa-card)" ];then
          echo "rr-config-script: PulseAudio module-udev-detect loaded, setting a volume of "${RR_AUDIO_VOLUME}"%"
          echo "rr-config-script: PulseAudio will use sink "$(pactl list sinks short)
        else
          echo "rr-config-script: PulseAudio module-udev-detect failed to load"
        fi
      else
        pactl load-module module-alsa-sink device="${RR_AUDIO_DEVICE}" name="temp_sink" ${TSCHED} > /dev/null
        pactl set-sink-volume alsa_output.temp_sink ${RR_AUDIO_VOLUME}%
        if [ ! -z "$(pactl list modules short | grep module-alsa-sink)" ];then
          echo "rr-config-script: PulseAudio module-alsa-sink loaded, setting a volume of "${RR_AUDIO_VOLUME}"%"
          echo "rr-config-script: PulseAudio will use sink "$(pactl list sinks short)
        else
          echo "rr-config-script: PulseAudio module-alsa-sink failed to load"
        fi
      fi
    fi
  fi
}

# Unload PulseAudio sink
pulseaudio_sink_unload() {
  
  if [ ${RR_AUDIO_BACKEND} = "PulseAudio" ]; then
    if [ "${RR_PA_UDEV}" = "true" ] && [ ! -z "$(pactl list modules short | grep module-alsa-card)" ]; then
      pactl set-sink-volume "$(pactl info | grep 'Default Sink:' | cut -d ' ' -f 3)" 100%  
      pactl unload-module module-udev-detect
      pactl unload-module module-alsa-card
      echo "rr-config-script: PulseAudio module-udev-detect unloaded"
    elif [ "${RR_PA_UDEV}" = "false" ] && [ ! -z "$(pactl list modules short | grep module-alsa-sink)" ]; then
      pactl set-sink-volume alsa_output.temp_sink 100%
      NUMBER="$(pactl list modules short | grep "name=temp_sink" | awk '{print $1;}')"
      if [ -n "${NUMBER}" ]; then
        pactl unload-module "${NUMBER}"
      fi
      echo "rr-config-script: PulseAudio module-alsa-sink unloaded"
    else
      echo "rr-config-script: neither the PulseAudio module module-alsa-card or module-alsa-sink was found. Nothing to unload"
    fi

    # Restore ALSA Master volume to 100%
    if [ ! -z "$(amixer | grep "'Master',0")" ] && [ ! $(amixer get Master | awk '$0~/%/{print $4}' | tr -d '[]%') = "100" ]; then
      amixer -q set Master,0 100% unmute
      echo "rr-config-script: ALSA mixer restore volume to 100%"
    fi
  fi
}

# Start FluidSynth
fluidsynth_service_start() {
  
  if [ ${RR_AUDIO_BACKEND} = "PulseAudio" ] && [ ! "$(systemctl is-active fluidsynth)" = "active" ]; then
    systemctl start fluidsynth
    if [ "$(systemctl is-active fluidsynth)" = "active" ]; then 
      echo "rr-config-script: FluidSynth service loaded successfully"
    else
      echo "rr-config-script: FluidSynth service failed to load"
    fi
  fi
}

# Stop FluidSynth
fluidsynth_service_stop() {
  

  if [ "$(systemctl is-active fluidsynth)" = "active" ]; then
    systemctl stop fluidsynth
    if [ ! "$(systemctl is-active fluidsynth)" = "active" ]; then 
      echo "rr-config-script: FluidSynth service successfully stopped"
    else
      echo "rr-config-script: FluidSynth service failed to stop"
    fi
  fi
}

# SDL2: Set audio driver to Pulseaudio or ALSA
set_SDL_audiodriver() {
  
  if [ ${RR_AUDIO_BACKEND} = "PulseAudio" ]; then
    export SDL_AUDIODRIVER=pulseaudio
  else
    export SDL_AUDIODRIVER=alsa
  fi
  echo "rr-config-script: SDL2 set environment variable SDL_AUDIODRIVER="${SDL_AUDIODRIVER}
}

# RETROARCH: Set audio & midi driver
set_RA_audiodriver() {
  
  RETROARCH_HOME=/storage/.config/retroarch
  RETROARCH_CONFIG=${RETROARCH_HOME}/retroarch.cfg

  if [ -f ${RETROARCH_CONFIG} ]; then
    if [ ${RR_AUDIO_BACKEND} = "PulseAudio" ]; then
      sed -e "s/audio_driver = \"alsathread\"/audio_driver = \"pulse\"/" -i ${RETROARCH_CONFIG}
      sed -e "s/midi_driver = \"null\"/midi_driver = \"alsa\"/" -i          ${RETROARCH_CONFIG}
      sed -e "s/midi_output = \"Off\"/midi_output = \"FluidSynth\"/" -i     ${RETROARCH_CONFIG}
      echo "rr-config-script: Retroarch force audio driver to PulseAudio & MIDI output to FluidSynth"
    else
      sed -e "s/audio_driver = \"pulse\"/audio_driver = \"alsathread\"/" -i ${RETROARCH_CONFIG}
      sed -e "s/midi_driver = \"alsa\"/midi_driver = \"null\"/" -i          ${RETROARCH_CONFIG}
      sed -e "s/midi_output = \"FluidSynth\"/midi_output = \"Off\"/" -i     ${RETROARCH_CONFIG}
      echo "rr-config-script: Retroarch force audio driver to ALSA & disable MIDI output"
    fi
  fi
}

case "$1" in
	"pulseaudio")
		RR_AUDIO_BACKEND="PulseAudio"
		pulseaudio_sink_unload
		pulseaudio_sink_load
	;;
	"fluidsynth")
		RR_AUDIO_BACKEND="PulseAudio"
		pulseaudio_sink_unload
		pulseaudio_sink_load
		fluidsynth_service_stop
		fluidsynth_service_start
	;;
	"alsa")
		RR_AUDIO_BACKEND="alsa"
		pulseaudio_sink_unload
		fluidsynth_service_stop
	;;
esac
		set_SDL_audiodriver
