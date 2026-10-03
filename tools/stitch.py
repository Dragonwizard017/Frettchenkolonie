#!/usr/bin/env python3
"""6 Cubemap-Seiten (Godot, Kamera blickt -Z) -> Equirect-Streifen.
Mapping (muss mit panorama.gdshader übereinstimmen):
    lon = atan2(d.x, -d.z)   (0 = Blick nach -Z, wächst Richtung +X)
    lat = asin(d.y)
    u = lon/(2*pi) + 0.5 ;  v = 0.5 - lat/(2*lat_max)   (nur |lat| <= lat_max)
usage: stitch.py <prefix> <out.jpg> [W] [lat_max_deg]
"""
import sys, numpy as np, cv2

prefix, out = sys.argv[1], sys.argv[2]
W = int(sys.argv[3]) if len(sys.argv) > 3 else 6144
lat_max = np.radians(float(sys.argv[4]) if len(sys.argv) > 4 else 45.0)
H = int(round(W * (2 * lat_max) / (2 * np.pi)))

# Vorwärts f, hoch u, rechts r = f x u  (wie Godot-Kamera)
faces = {
    "front": ((0, 0, -1), (0, 1, 0)), "right": ((1, 0, 0), (0, 1, 0)),
    "back": ((0, 0, 1), (0, 1, 0)), "left": ((-1, 0, 0), (0, 1, 0)),
    "up": ((0, 1, 0), (0, 0, 1)), "down": ((0, -1, 0), (0, 0, -1)),
}
imgs = {k: cv2.imread(f"{prefix}_{k}.png", cv2.IMREAD_COLOR).astype(np.float32) for k in faces}
S = imgs["front"].shape[0]

xs = (np.arange(W) + 0.5) / W
ys = (np.arange(H) + 0.5) / H
lon = (xs - 0.5) * 2 * np.pi
lat = (0.5 - ys) * 2 * lat_max
LON, LAT = np.meshgrid(lon, lat)
d = np.stack([np.cos(LAT) * np.sin(LON), np.sin(LAT), -np.cos(LAT) * np.cos(LON)], axis=-1)

out_img = np.zeros((H, W, 3), np.float32)
best = np.full((H, W), -1.0, np.float32)
for k, (f, u) in faces.items():
    f = np.array(f, np.float32); u = np.array(u, np.float32); r = np.cross(f, u)
    df = d @ f
    mask = df > best           # Fläche mit größter Vorwärtskomponente gewinnt
    mask &= df > 1e-6
    a = (d @ r) / np.maximum(df, 1e-6)
    b = -(d @ u) / np.maximum(df, 1e-6)
    px = ((a + 1) * 0.5 * S - 0.5).astype(np.float32)
    py = ((b + 1) * 0.5 * S - 0.5).astype(np.float32)
    samp = cv2.remap(imgs[k], px, py, cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
    out_img[mask] = samp[mask]
    best[mask] = df[mask]

cv2.imwrite(out, np.clip(out_img, 0, 255).astype(np.uint8), [cv2.IMWRITE_JPEG_QUALITY, 90])
print("geschrieben", out, W, "x", H)
