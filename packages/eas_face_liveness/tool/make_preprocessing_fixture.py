#!/usr/bin/env python3
"""Generate synthetic OpenCV reference tensors; no face or personal image data.
Run after export_model.py. Requires opencv-python-headless, numpy.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--upstream-crop', type=Path, required=True)
args = parser.parse_args()
spec = importlib.util.spec_from_file_location('upstream_crop', args.upstream_crop)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
y, x = np.mgrid[:480, :640]
# RGB in Dart; OpenCV receives BGR.
rgb = np.stack([(x*3+y)%256, (x+y*2)%256, (x*2+y*3)%256], axis=-1).astype(np.uint8)
cases = []
for scale, box in [(scale, box) for scale in [2.7, 4.0] for box in [[50, 60, 80, 80], [0, 5, 90, 120], [540, 380, 100, 100]]]:
    patch = module.CropImage().crop(rgb[:, :, ::-1], box, scale, 80, 80)
    cases.append({'scale': scale, 'box': box, 'bgrChw': patch.transpose(2, 0, 1).flatten().tolist()})
path = Path(__file__).resolve().parents[1] / 'test/fixtures/preprocessing.json'
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(cases, separators=(',', ':')) + '\n')
print(path)
