from pathlib import Path
import base64
import re
import struct


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "FaceCaptureIOS" / "LQFaceCaptureViewController.m"
RESOURCE_DATA = ROOT / "FaceCaptureIOS" / "LQFaceCaptureResourceData.h"


def read_embedded_pngs():
    text = RESOURCE_DATA.read_text(encoding="utf-8")
    values = re.findall(r'LQFace(?:Guide|Switch)Base64\s*=\s*@"([A-Za-z0-9+/=]+)";', text)
    assert len(values) == 2, "both face guide and camera switch fallbacks must be embedded"
    return [base64.b64decode(value) for value in values]


def test_static_framework_resource_lookup_and_fallback():
    source = SOURCE.read_text(encoding="utf-8")
    assert "NSBundle.mainBundle.privateFrameworksPath" in source
    assert 'stringByAppendingPathComponent:@"UniFaceCapture.framework"' in source
    assert '#import "LQFaceCaptureResourceData.h"' in source

    expected_dimensions = [(512, 512), (128, 128)]
    for data, dimensions in zip(read_embedded_pngs(), expected_dimensions):
        assert data.startswith(b"\x89PNG\r\n\x1a\n")
        assert struct.unpack(">II", data[16:24]) == dimensions


if __name__ == "__main__":
    test_static_framework_resource_lookup_and_fallback()
    print("resource fallback regression: PASS")
