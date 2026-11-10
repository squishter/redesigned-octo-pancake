"""Shared triangle geometry and portable three-group GLB export."""

import json
import math
import struct

import numpy as np

PALETTE = ["#f8f5ee", "#527447", "#8caa68", "#db8ca6", "#e5b956", "#adc27b", "#749455"]


def unit(v):
    v = np.asarray(v, dtype=float)
    return v / max(1e-12, np.linalg.norm(v))


def frame(axis, normal=(0., 0., 1.)):
    """Local +Y follows the organ's attachment axis; +Z is its face."""
    y = unit(axis)
    z = np.asarray(normal, dtype=float) - y * np.dot(y, normal)
    if np.linalg.norm(z) < .01:
        z = np.cross(y, (1., 0., 0.))
    z = unit(z)
    return np.column_stack((unit(np.cross(y, z)), y, z))


class Mesh:
    def __init__(self):
        self.vertices = []
        self.triangles = []
        self.labels = []
        self.parts = []
        self.attachments = []

    def add(self, points, faces, label, part, matrix=None, offset=None):
        points = np.asarray(points, dtype=float)
        if matrix is not None:
            points = points @ matrix.T
        if offset is not None:
            points = points + offset
        base = len(self.vertices)
        self.vertices.extend(points.tolist())
        self.triangles.extend((np.asarray(faces, dtype=int) + base).tolist())
        self.labels.extend([label] * len(points))
        self.parts.extend([part] * len(points))

    def merge(self, other, matrix=None, offset=None):
        points = np.asarray(other.vertices)
        if matrix is not None:
            points = points @ matrix.T
        if offset is not None:
            points += offset
        base = len(self.vertices)
        self.vertices.extend(points.tolist())
        self.triangles.extend((np.asarray(other.triangles, dtype=int) + base).tolist())
        self.labels.extend(other.labels)
        self.parts.extend(other.parts)

    def data(self, metadata):
        return dict(vertices=self.vertices, triangles=self.triangles,
                    labels=self.labels, parts=self.parts, attachments=self.attachments,
                    metadata=metadata, palette=PALETTE)


def tube(mesh, path, radius, label, part):
    points, faces = [], []
    path = np.asarray(path)
    sides = 8
    for i, p in enumerate(path):
        tangent = path[min(len(path) - 1, i + 1)] - path[max(0, i - 1)]
        basis = frame(tangent)
        r = radius * (1 - .42 * i / (len(path) - 1))
        for j in range(sides):
            a = math.tau * j / sides
            points.append(p + basis @ (r * math.cos(a), 0., r * math.sin(a)))
        if i:
            for j in range(sides):
                a = (i - 1) * sides + j
                b = (i - 1) * sides + (j + 1) % sides
                faces.extend(((a, b, b + sides), (a, b + sides, a + sides)))
    points.extend((path[0], path[-1]))
    for j in range(sides):
        faces.append((len(points) - 2, (j + 1) % sides, j))
        a = (len(path) - 1) * sides
        faces.append((len(points) - 1, a + j, a + (j + 1) % sides))
    mesh.add(points, faces, label, part)


def ellipsoid(mesh, center, radii, label, part):
    points, faces = [], []
    rings, sides = 8, 16
    for i in range(rings + 1):
        a = math.pi * i / rings
        for j in range(sides):
            b = math.tau * j / sides
            points.append(np.asarray(center) + np.asarray(radii) *
                          (math.sin(a) * math.cos(b), math.cos(a), math.sin(a) * math.sin(b)))
    for i in range(rings):
        for j in range(sides):
            a, b = i * sides + j, i * sides + (j + 1) % sides
            if i > 0:
                faces.append((a, b, b + sides))
            if i < rings - 1:
                faces.append((a, b + sides, a + sides))
    mesh.add(points, faces, label, part)


def write_glb(mesh, path, metadata):
    """Portable three-group GLB; preserves unlit semantic colors and normals."""
    vertices = np.asarray(mesh.vertices, dtype=np.float32)
    triangles = np.asarray(mesh.triangles, dtype=np.uint32)
    normals = np.zeros_like(vertices)
    face_normals = np.cross(vertices[triangles[:, 1]] - vertices[triangles[:, 0]],
                            vertices[triangles[:, 2]] - vertices[triangles[:, 0]])
    for column in range(3):
        np.add.at(normals, triangles[:, column], face_normals)
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
    binary, views, accessors = bytearray(), [], []

    def accessor(values, kind, component):
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        raw = values.tobytes()
        binary.extend(raw)
        view = len(views)
        views.append(dict(buffer=0, byteOffset=offset, byteLength=len(raw)))
        entry = dict(bufferView=view, componentType=component, count=len(values), type=kind)
        if kind == "VEC3":
            entry.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        accessors.append(entry)
        return len(accessors) - 1

    positions = accessor(vertices.astype("<f4"), "VEC3", 5126)
    normal_id = accessor(normals.astype("<f4"), "VEC3", 5126)
    materials = []
    for color in PALETTE:
        rgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        materials.append(dict(pbrMetallicRoughness=dict(baseColorFactor=rgb + [1.],
                                                       metallicFactor=0, roughnessFactor=1),
                              doubleSided=True, extensions={"KHR_materials_unlit": {}}))
    meshes, nodes = [], []
    triangle_labels = np.asarray(mesh.labels)[triangles[:, 0]]
    for group, labels in (("Stems", [1]), ("Leaves", [2, 6]), ("Flowers", [3, 4, 5])):
        primitives = []
        for label in labels:
            selected = triangles[triangle_labels == label].reshape(-1).astype("<u4")
            if len(selected):
                index_id = accessor(selected, "SCALAR", 5125)
                primitives.append(dict(attributes={"POSITION": positions, "NORMAL": normal_id},
                                       indices=index_id, material=label))
        if primitives:
            nodes.append(dict(name=group, mesh=len(meshes)))
            meshes.append(dict(name=group, primitives=primitives))
    document = dict(asset=dict(version="2.0", generator="Paint With Gems modular plant study"),
                    extensionsUsed=["KHR_materials_unlit"], scene=0,
                    scenes=[dict(nodes=list(range(len(nodes))))], nodes=nodes, meshes=meshes,
                    materials=materials, buffers=[dict(byteLength=len(binary))],
                    bufferViews=views, accessors=accessors, extras=metadata)
    header = json.dumps(document, separators=(",", ":")).encode()
    header += b" " * (-len(header) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    total = 12 + 8 + len(header) + 8 + len(binary)
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, total) +
                     struct.pack("<II", len(header), 0x4E4F534A) + header +
                     struct.pack("<II", len(binary), 0x004E4942) + binary)
