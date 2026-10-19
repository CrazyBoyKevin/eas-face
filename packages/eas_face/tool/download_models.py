#!/usr/bin/env python3
"""Build-time download only. Pin source revision, size and SHA-256."""
from pathlib import Path
import hashlib
import urllib.request
import runpy

ROOT = Path(__file__).resolve().parents[1]
REVISION = '47534e27c9851bb1128ccc0102f1145e27f23f98'
MODELS = [
    ('face_detection_yunet', 'face_detection_yunet_2023mar.onnx', 232589,
     '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4'),
]

def download():
    (ROOT / 'assets/models').mkdir(parents=True, exist_ok=True)
    (ROOT / 'licenses').mkdir(exist_ok=True)
    for folder, name, size, digest in MODELS:
        dest = ROOT / 'assets/models' / name
        if not (dest.exists() and dest.stat().st_size == size
                and hashlib.sha256(dest.read_bytes()).hexdigest() == digest):
            url = f'https://media.githubusercontent.com/media/opencv/opencv_zoo/{REVISION}/models/{folder}/{name}'
            print(f'Downloading {name}...', flush=True)
            data = urllib.request.urlopen(url, timeout=120).read()
            if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
                raise RuntimeError(f'Integrity check failed: {name}')
            temp = dest.with_suffix('.tmp')
            temp.write_bytes(data)
            temp.replace(dest)
        print(f'Verified {name}', flush=True)
        license_path = ROOT / 'licenses' / f'{folder}.LICENSE'
        if not license_path.exists():
            url = f'https://raw.githubusercontent.com/opencv/opencv_zoo/{REVISION}/models/{folder}/LICENSE'
            license_path.write_bytes(urllib.request.urlopen(url, timeout=30).read())
    runpy.run_path(str(ROOT / 'tool/prepare_intel_model.py'), run_name='__main__')

if __name__ == '__main__':
    download()
