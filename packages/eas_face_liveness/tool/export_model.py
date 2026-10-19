#!/usr/bin/env python3
"""Pinned upstream -> ONNX, numerical parity and local CPU timing (not phone).
Requires torch, onnx, onnxruntime, numpy. No user images are read or uploaded.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import time
import urllib.request
import numpy as np
import onnx
import onnxruntime as ort
import torch

COMMIT = 'b6d5f04ad78778917853b25c778acef6d5626d15'
ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
 'src/model_lib/MiniFASNet.py': 'e498c4ec5e1ddfaba62b941a126c19d65aa564999f3309661fe43ee8bf38acd7',
 'resources/anti_spoof_models/2.7_80x80_MiniFASNetV2.pth': 'a5eb02e1843f19b5386b953cc4c9f011c3f985d0ee2bb9819eea9a142099bec0',
 'resources/anti_spoof_models/4_0_0_80x80_MiniFASNetV1SE.pth': '84ee1d37d96894d5e82de5a57df044ef80a58be2b218b5ed7cdfd875ec2f5990',
 'LICENSE': 'daf94bf1dc9cc5700fe5af2c7c0cbd1836e70d509ed78fd0bebef7432edee6fb',
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--model', choices=['v2', 'v1se'], default='v2')
    args = parser.parse_args()
    context = args.model == 'v1se'
    files = ['src/model_lib/MiniFASNet.py',
             ('resources/anti_spoof_models/4_0_0_80x80_MiniFASNetV1SE.pth' if context else
              'resources/anti_spoof_models/2.7_80x80_MiniFASNetV2.pth'), 'LICENSE']
    hashes = {}
    for name in files:
        path = args.cache / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            urllib.request.urlretrieve(f'https://raw.githubusercontent.com/minivision-ai/Silent-Face-Anti-Spoofing/{COMMIT}/{name}', path)
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        if hashes[name] != EXPECTED[name]:
            raise ValueError(f'Upstream hash mismatch: {name}')
    spec = importlib.util.spec_from_file_location('minifasnet', args.cache / files[0])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    model_type = module.MiniFASNetV1SE if context else module.MiniFASNetV2
    model = model_type(conv6_kernel=(5, 5))
    state = torch.load(args.cache / files[1], map_location='cpu', weights_only=True)
    model.load_state_dict({k.removeprefix('module.'): v for k, v in state.items()})
    model.eval()
    torch.set_num_threads(2)
    output = ROOT / ('assets/models/minifasnet_v1se.onnx' if context else 'assets/models/minifasnet_v2.onnx')
    output.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(model, torch.zeros(1, 3, 80, 80), str(output),
                      input_names=['input'], output_names=['logits'],
                      opset_version=17, dynamo=False)
    graph = onnx.load(output)
    onnx.checker.check_model(graph)
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(output), options, providers=['CPUExecutionProvider'])
    rng = np.random.default_rng(20261016)
    fixtures = [np.zeros((1, 3, 80, 80), np.float32),
                np.full((1, 3, 80, 80), 128, np.float32),
                rng.integers(0, 256, (1, 3, 80, 80)).astype(np.float32)]
    errors = []
    for data in fixtures:
        with torch.no_grad(): expected = model(torch.from_numpy(data)).numpy()
        actual = session.run(None, {'input': data})[0]
        np.testing.assert_allclose(actual, expected, atol=5e-4, rtol=5e-4)
        errors.append(float(np.max(np.abs(actual - expected))))
    for _ in range(20): session.run(None, {'input': fixtures[-1]})
    samples = []
    for _ in range(200):
        start = time.perf_counter()
        session.run(None, {'input': fixtures[-1]})
        samples.append((time.perf_counter() - start) * 1000)
    report = {'model': model_type.__name__, 'crop_scale': 4.0 if context else 2.7, 'upstream_commit': COMMIT, 'source_sha256': hashes,
              'onnx_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
              'onnx_bytes': output.stat().st_size, 'opset': 17, 'ir_version': graph.ir_version,
              'input': 'float32 BGR NCHW [1,3,80,80], 0..255; no normalization',
              'output': 'three logits; live class index 1; apply softmax once',
              'max_abs_errors': errors, 'benchmark_platform': platform.platform(),
              'torch': torch.__version__, 'onnxruntime': ort.__version__,
              'cpu_threads': 2, 'warmup': 20, 'iterations': 200,
              'inference_p50_ms': float(np.percentile(samples, 50)),
              'inference_p95_ms': float(np.percentile(samples, 95)),
              'benchmark_note': 'Synthetic input, desktop CPU inference only. Not camera, Flutter or mobile latency; not an accuracy test.'}
    (ROOT / ('MODEL_CONTEXT_MANIFEST.json' if context else 'MODEL_MANIFEST.json')).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))

if __name__ == '__main__': main()
