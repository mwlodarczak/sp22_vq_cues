# extract_vq.praat -- Extract voice quality parameters
# Copyright (C) 2021 Marcin Włodarczak
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


form Calculate VQ features
  sentence wav_path /Users/marcin/
  sentence outdir /Users/marcin/
  positive freq_min 60
  positive freq_max 330
  positive frame_step 0.002
  positive cpps_time_smooth_bins 5
  positive cpps_quef_smooth_bins 10
  positive spec_max_freq 7000
  integer hrf_nharm 10
endform

frame_dur = 3 / freq_min

wav_id = Read from file: wav_path$
# File name without the extension.
fname_short$ = selected$("Sound")

start_time = Get start time
end_time = Get end time
dur = Get total duration

# == Get pitch ==
@get_f0: wav_id, frame_step
writeInfoLine: "Pitch done"

# === Get CPPS ===

# Get power cepstrogram and smooth it
select wav_id
power_cepstr_id = To PowerCepstrogram: freq_min, frame_step, 5000, 50

# Smooth the cepstrogram
time_smooth_win = cpps_time_smooth_bins * frame_step
quef_step = Get quefrency step
quef_smooth_win = cpps_quef_smooth_bins * quef_step
power_cepstr_smooth_id = Smooth: time_smooth_win, quef_smooth_win
n_frames = Get number of frames

# Remove the unsmoothed cepstrogram.
selectObject: power_cepstr_id
Remove

# Create a table 
header$ = "time pitch intensity cpps alpha h1h2 hrf vuv"
vq_table_id = Create Table with column names: "vq", n_frames, header$

for i from 1 to n_frames
  selectObject: power_cepstr_smooth_id
  frame_time = Get time from frame number: i
  cepstrum_frame_id = To PowerCepstrum (slice): frame_time
  selectObject: cepstrum_frame_id
  frame_cpps = Get peak prominence: freq_min, freq_max, "Parabolic", 0.001, 0.0, "Straight", "Robust"
  Remove

  selectObject: vq_table_id
  Set string value: i, "time", fixed$(frame_time, 3)
  Set string value: i, "cpps", fixed$(frame_cpps, 3)
  endfor

selectObject: power_cepstr_smooth_id
Remove
writeInfoLine: "CPPS done"

# == Get voicing decisions ==

selectObject: wav_id
pitch_vuv_id = To Pitch (ac): frame_step, 50, 15, "no", 0.015, 0.25, 0.01, 0.35, 0.4, 800

# === Get spectral measures===

# Note that with a 50-ms frame, the effective time step in Praat is
# 50 / (8 * sqrt(pi)) = 3.5 ms rather than the 2 ms above.

selectObject: wav_id
spectr_id = To Spectrogram: frame_dur, spec_max_freq, frame_step, 20, "Gaussian"

for i from 1 to n_frames
  selectObject: vq_table_id
  frame_time = Get value: i, "time"
  selectObject: get_f0.pitch_id
  frame_pitch = Get value at time: frame_time, "Hertz", "linear"
  selectObject: pitch_vuv_id
  frame_pitch_vuv = Get value at time: frame_time, "Hertz", "linear"

  if frame_pitch_vuv = undefined
    selectObject: vq_table_id
    Set string value: i, "pitch", "NA"
    Set string value: i, "alpha", "NA"
    Set string value: i, "h1h2", "NA"
    Set string value: i, "hrf", "NA"
    Set string value: i, "vuv", "0"

  else

    # Extract a spectral slice
    selectObject: spectr_id
    spectrum_id = To Spectrum (slice): frame_time

    # Calculate alpha
    alpha = Get band energy difference: 0, 1000, 1000, 5000

    if frame_pitch = undefined
      selectObject: vq_table_id
      Set string value: i, "pitch", "NA"
      Set string value: i, "alpha", fixed$(alpha, 3)
      Set string value: i, "h1h2", "NA"
      Set string value: i, "hrf", "NA"
      Set string value: i, "vuv", "1"

    else

      # Calculate H1H2
      
      selectObject: spectrum_id
      ltas_id = To Ltas (1-to-1)
      
      @get_harm_energy: 1, spectrum_id, ltas_id, frame_pitch
      h1 = get_harm_energy.harm_energy
      @get_harm_energy: 2, spectrum_id, ltas_id, frame_pitch
      h2 = get_harm_energy.harm_energy
      h1h2 = 10 * log10(h1 / h2)
      
      # Calculate HRF
      
      harm_sum = 0
      for harm_i from 2 to hrf_nharm
        @get_harm_energy: harm_i, spectrum_id, ltas_id, frame_pitch
        if get_harm_energy.harm_energy != undefined
          harm_sum += get_harm_energy.harm_energy
        endif
      endfor
      hrf = 10 * log10(harm_sum / h1)
      
      selectObject: ltas_id
      Remove

      selectObject: vq_table_id
      Set string value: i, "pitch", fixed$(frame_pitch, 3)
      Set string value: i, "alpha", fixed$(alpha, 3)
      Set string value: i, "h1h2", fixed$(h1h2, 3)
      Set string value: i, "hrf", fixed$(hrf, 3)
      Set string value: i, "vuv", "1"

    endif

    selectObject: spectrum_id
    Remove
  endif
endfor
writeInfoLine: "Spectr done"

selectObject: get_f0.pitch_id, pitch_vuv_id
Remove

# Get intensity
selectObject: wav_id
int_id = To Intensity: 64, frame_step, "yes"
# int_id = To Intensity: get_f0.f0_min, frame_step, "yes"
selectObject: vq_table_id

for i from 1 to n_frames
  selectObject: vq_table_id
  frame_time = Get value: i, "time"
  selectObject: int_id
  int = Get value at time: frame_time, "cubic"
  selectObject: vq_table_id
  Set string value: i, "intensity", fixed$(int, 3)
endfor
selectObject: int_id
Remove

selectObject: vq_table_id
Save as comma-separated file: outdir$ + "/" + fname_short$ + "_vq.csv"
plusObject: wav_id
Remove

procedure get_f0: .sound_id, .frame_step

  # The following is a modified version of the f0 estimation method 
  # implemented in the Prosogram (https://sites.google.com/site/prosogram/).
  
  # == Pass 1 ==

  selectObject: .sound_id
  .pitch_id = To Pitch (ac): 0.01, 65, 15, "no", 0.015, 0.45, 0.01, 0.35, 0.14, 800

  .p50 = Get quantile: 0, 0, 0.50, "Hertz"
  removeObject: .pitch_id
  # Pitch floor: 12 ST below median pitch, with minimum of 50 Hz
  .f0_min = floor(max(semitonesToHertz(hertzToSemitones(.p50) - 12), 50))    
  # Pitch ceiling: 18 ST above median pitch, with maximum of 1000 Hz 
  .f0_max = floor(min(semitonesToHertz(hertzToSemitones(.p50) + 18), 1000))

  # == Pass 2 ==
  selectObject: .sound_id
  .pitch_id = To Pitch (ac): .frame_step, .f0_min, 15, "no", 0.015, 0.45, 0.01, 0.35, 0.14, .f0_max
  
endproc

procedure get_harm_energy: .nharm, .spectrum_id, .ltas_id, .f0
  selectObject: .ltas_id
  .harm_err = .f0 / 10
  .peak_freq = Get frequency of maximum: .nharm * .f0 - .harm_err, .nharm * .f0 + .harm_err, "none"
  selectObject: .spectrum_id
  nbins =  Get number of bins
  .peak_bin = Get bin number from frequency: .peak_freq
  if nbins < round(.peak_bin)
    .harm_energy = undefined
  else
    .harm_real = Get real value in bin: round(.peak_bin)
    .harm_imag = Get imaginary value in bin: round(.peak_bin)
    .harm_energy = .harm_real**2 + .harm_imag**2
  endif
endproc
