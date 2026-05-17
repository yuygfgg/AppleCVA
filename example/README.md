# Camera Viewer

Opens the default camera, runs Vision face detection, feeds the detected face rectangles into AppleCVA, and draws the tracked face rectangle, landmarks, and the strongest blendshape values.

## Environment Variables

| Variable         | Default | Effect                                       |
| ---------------- | ------- | -------------------------------------------- |
| `APPLECVA_TRACE` | unset   | Print AppleCVA wrapper trace logs to stderr. |

## Keyboard Shortcuts

The camera viewer window must be focused.

| Key | Action                                                                                                      |
| --- | ----------------------------------------------------------------------------------------------------------- |
| `x` | Toggle mirrored preview and overlay.                                                                        |
| `p` | Toggle camera preview visibility while keeping the overlay/status text.                                     |
| `y` | Toggle landmark Y-axis flip within the detected landmark bounds.                                            |
| `b` | Toggle face rectangle and landmark coordinate origin handling between top-left and bottom-left conventions. |
| `e` | Toggle One Euro Filter smoothing for the displayed tracking result.                                         |

## Build & Run

```sh
make build/camera_viewer
./build/camera_viewer
./build/camera_viewer --full
```
