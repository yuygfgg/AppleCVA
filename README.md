# AppleCVA VTS Source

macOS VTube Studio tracking source based on AppleCVA face tracking.

## Build

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

## Run

```sh
./build/vts_source [--host 127.0.0.1] [--port 8001] [--full] [--no-filter] [--no-custom] [--no-arkit-aliases] [--acva-blendshapes]
```

Calibration is required before the app connects to VTube Studio or injects tracking parameters. Start the app, keep a neutral expression, look straight at the camera, and press `Calibrate First` button or `c` key.

The app injects available default VTS tracking parameters and, by default, creates full ARKit-style aliases plus a small set of derived `ACVA...` custom parameters. Use `--no-custom` to inject only default VTS parameters, `--no-arkit-aliases` to disable alias custom parameters, or `--acva-blendshapes` to fill remaining custom slots with raw `ACVA...` blendshape channels.

## Preview Controls

The preview window must be focused.

| Key | Action                                                              |
| --- | ------------------------------------------------------------------- |
| `x` | Toggle mirrored preview and overlay.                                |
| `p` | Toggle camera preview visibility while keeping overlay/status text. |
| `y` | Toggle landmark Y-axis flip within the detected landmark bounds.    |
| `b` | Toggle face rectangle and landmark coordinate origin handling.      |
| `e` | Toggle One Euro Filter smoothing for both preview and emitted data. |
| `c` | Calibrate neutral pose.                                             |
