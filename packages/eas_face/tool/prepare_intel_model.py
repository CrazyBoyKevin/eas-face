#!/usr/bin/env python3
"""Build-time only: verify packaged ONNX, or reproduce it from pinned Intel IR.

For regeneration use Python 3.12 and conversion-requirements.txt.
No user images are accessed. Runtime SDK never downloads models.
"""
from pathlib import Path
import hashlib
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
NAME = 'face-reidentification-retail-0095'
SIZE = 4466624
SHA256 = 'd351ea020acbbd3992b69edc673a0e667623e697745b6c1a23e67085cf90e929'
BASE = 'https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1'
SOURCES = {
    'xml': (237585, 'd5adadadf98f45459bf740b0d5cb425b029ef81133280d3b4f9d0ba0d565b8e21b834c3d030448b8926d849340a8ca7a'),
    'bin': (4427256, '953bb75f16d4e7faa0a19700871e6107726cb83e0e062215a841848335694a1e274c61efacab81b4d240d935fe30efda'),
}


def valid(path):
    return (path.is_file() and path.stat().st_size == SIZE
            and hashlib.sha256(path.read_bytes()).hexdigest() == SHA256)


def canonicalize(path):
    """Stabilize converter's unordered traversal without changing operations."""
    import onnx
    import networkx as nx
    model = onnx.load(path)
    nodes = {node.name: node for node in model.graph.node}
    if len(nodes) != len(model.graph.node):
        raise RuntimeError('Duplicate node names in converted model')
    producer = {value: node.name for node in model.graph.node for value in node.output}
    graph = nx.DiGraph()
    graph.add_nodes_from(nodes)
    for node in model.graph.node:
        graph.add_edges_from((producer[value], node.name) for value in node.input if value in producer)
    ordered = [nodes[name] for name in nx.lexicographical_topological_sort(graph)]
    del model.graph.node[:]
    model.graph.node.extend(ordered)
    info = sorted(model.graph.value_info, key=lambda entry: entry.name)
    del model.graph.value_info[:]
    model.graph.value_info.extend(info)
    onnx.checker.check_model(model)
    onnx.save(model, path)


def prepare():
    dest = ROOT / 'assets/models' / f'{NAME}.onnx'
    if valid(dest):
        print(f'Verified {dest.name}')
        return
    try:
        import openvino2onnx  # noqa: F401
    except ImportError as error:
        raise RuntimeError('Install tool/conversion-requirements.txt in Python 3.12 to regenerate the missing model.') from error
    with tempfile.TemporaryDirectory(prefix='eas-face-convert-') as directory:
        work = Path(directory)
        for suffix, (size, digest) in SOURCES.items():
            data = urllib.request.urlopen(f'{BASE}/{NAME}/FP32/{NAME}.{suffix}', timeout=120).read()
            if len(data) != size or hashlib.sha384(data).hexdigest() != digest:
                raise RuntimeError(f'Intel source integrity failure: {suffix}')
            (work / f'{NAME}.{suffix}').write_bytes(data)
        output = work / f'{NAME}.onnx'
        subprocess.run([sys.executable, '-m', 'openvino2onnx', str(work / f'{NAME}.xml'),
                        str(output), '--opset-version', '17'], check=True)
        canonicalize(output)
        if not valid(output):
            raise RuntimeError('Converted model differs from verified artifact; do not replace without parity testing.')
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(output.read_bytes())


if __name__ == '__main__':
    prepare()
