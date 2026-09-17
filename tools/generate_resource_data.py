from base64 import b64encode
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = [
    ("LQFaceGuideBase64", ROOT / "FaceCaptureIOS" / "face_guide_overlay.png"),
    ("LQFaceSwitchBase64", ROOT / "FaceCaptureIOS" / "camera_switch.png"),
]
OUTPUT = ROOT / "FaceCaptureIOS" / "LQFaceCaptureResourceData.h"


lines = ["#import <Foundation/Foundation.h>", ""]
for symbol, path in RESOURCES:
    encoded = b64encode(path.read_bytes()).decode("ascii")
    lines.append(f'static NSString * const {symbol} = @"{encoded}";')
    lines.append("")
OUTPUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
