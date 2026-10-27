#!/usr/bin/env python3
"""Convert a GLB/glTF scene into a compact, native Metal triangle stream.

Inputs may reference split .bin buffers, as in Merk of Duty's deployed
nuketown_2020_optimized.glb file. Converts uncompressed glTF TRIANGLES, index
buffers, node transforms and base colors. No third-party Python dependencies.

Usage:
 python3 Tools/convert_gltf.py recovered-pages/nuketown_2020_optimized.glb \
   --out MerkOfDuty/Resources/MerkMap.meshbin --scale 0.01 --max-triangles 100000

Color textures, skeletal animation and the exported collision BVH are NOT
converted by this tool. Those are separate engineering tasks.
"""
import argparse
from io import BytesIO
import base64
import json
import math
import struct
from pathlib import Path
from urllib.parse import unquote

MAGIC = b'MERKMAP1'
TEXTURED_MAGIC = b'MERKMAP2'
FMT = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
NUM = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def matmul(a, b):
    return [sum(a[k*4+r] * b[c*4+k] for k in range(4)) for c in range(4) for r in range(4)]


def identity():
    return [1.,0,0,0,0,1.,0,0,0,0,1.,0,0,0,0,1.]


def local_matrix(node):
    if 'matrix' in node:
        return [float(x) for x in node['matrix']]
    x,y,z,w = node.get('rotation', [0,0,0,1])
    sx,sy,sz = node.get('scale', [1,1,1])
    tx,ty,tz = node.get('translation', [0,0,0])
    rotation = [
        1-2*(y*y+z*z), 2*(x*y+z*w), 2*(x*z-y*w), 0,
        2*(x*y-z*w), 1-2*(x*x+z*z), 2*(y*z+x*w), 0,
        2*(x*z+y*w), 2*(y*z-x*w), 1-2*(x*x+y*y), 0,
        0,0,0,1
    ]
    scale = [sx,0,0,0,0,sy,0,0,0,0,sz,0,0,0,0,1]
    m = matmul(rotation, scale)
    m[12:15] = [tx, ty, tz]
    return m


def transform(m, v):
    x,y,z = v
    return (m[0]*x + m[4]*y + m[8]*z + m[12],
            m[1]*x + m[5]*y + m[9]*z + m[13],
            m[2]*x + m[6]*y + m[10]*z + m[14])


def normalize(v):
    length = math.sqrt(sum(x*x for x in v)) or 1
    return [x/length for x in v]


def cross(a,b):
    return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])


def load_gltf(path):
    data = path.read_bytes()
    glb_buffer = None
    if data[:4] == b'glTF':
        if len(data) < 20: raise ValueError('Truncated GLB')
        magic, version, total = struct.unpack_from('<4sII', data)
        if version != 2 or total > len(data): raise ValueError('GLB 2.0 expected')
        cursor, manifest = 12, None
        while cursor + 8 <= total:
            n, tag = struct.unpack_from('<I4s', data, cursor)
            cursor += 8
            chunk = data[cursor:cursor+n]
            cursor += n
            if tag == b'JSON': manifest = json.loads(chunk)
            elif tag == b'BIN\0': glb_buffer = chunk
        if manifest is None: raise ValueError('No glTF JSON chunk')
    else:
        manifest = json.loads(data)
    buffers = []
    for entry in manifest.get('buffers', []):
        uri = entry.get('uri')
        if uri is None:
            if glb_buffer is None: raise ValueError('Missing GLB binary data')
            raw = glb_buffer
        elif uri.startswith('data:'):
            raw = base64.b64decode(uri.split(',',1)[1])
        else:
            local = (path.parent / unquote(uri)).resolve()
            if not local.is_relative_to(path.parent.resolve()): raise ValueError('Unsafe buffer path')
            raw = local.read_bytes()
        if len(raw) < entry.get('byteLength',0): raise ValueError('Short buffer: ' + str(uri))
        buffers.append(raw)
    return manifest, buffers


def accessor_values(doc, buffers, index):
    a = doc['accessors'][index]
    if 'sparse' in a: raise ValueError('Sparse accessor unsupported')
    view = doc['bufferViews'][a['bufferView']]
    if a['componentType'] not in FMT or a['type'] not in NUM: raise ValueError('Unsupported accessor type')
    width = NUM[a['type']]
    f = '<' + FMT[a['componentType']] * width
    size = struct.calcsize(f)
    stride = view.get('byteStride',size)
    start = view.get('byteOffset',0) + a.get('byteOffset',0)
    raw = buffers[view['buffer']]
    if stride < size:
        raise ValueError('Accessor byteStride smaller than element size')
    if start < 0 or start + (a['count'] - 1) * stride + size > len(raw):
        raise ValueError('Accessor extends beyond its buffer')
    normalized = bool(a.get('normalized', False))
    component_type = a['componentType']
    if normalized and component_type not in (5120, 5121, 5122, 5123):
        raise ValueError('Normalized glTF accessor must use BYTE or SHORT components')
    # glTF section 3.6.2.1: signed normalized integers map -128/-32768
    # exactly to -1; unsigned integers map 0..255/65535 to 0..1.
    denominator = {5120:127.0, 5121:255.0, 5122:32767.0, 5123:65535.0}.get(component_type)
    result = []
    for i in range(a['count']):
        values = struct.unpack_from(f,raw,start+i*stride)
        if normalized:
            if component_type in (5120,5122):
                values = tuple(max(-1.0, value / denominator) for value in values)
            else:
                values = tuple(value / denominator for value in values)
        result.append(values)
    return result


def iter_meshes(doc):
    nodes=doc.get('nodes',[])
    scenes=doc.get('scenes',[])
    roots=scenes[doc.get('scene',0)].get('nodes',[]) if scenes else list(range(len(nodes)))
    def walk(idx,m):
        node=nodes[idx]
        model=matmul(m,local_matrix(node))
        if 'mesh' in node: yield (doc['meshes'][node['mesh']],model)
        for child in node.get('children',[]): yield from walk(child,model)
    for idx in roots: yield from walk(idx,identity())


def image_bytes(doc, buffers, source, base_dir):
    """Extract an embedded or local glTF image; never fetch URLs implicitly."""
    img = doc['images'][source]
    uri = img.get('uri')
    if uri is not None:
        if uri.startswith('data:'):
            return base64.b64decode(uri.split(',', 1)[1])
        if '://' in uri or uri.startswith('/'):
            raise ValueError('Remote or absolute texture URI is not supported')
        file = (base_dir / unquote(uri.split('?', 1)[0])).resolve()
        if not file.is_relative_to(base_dir.resolve()):
            raise ValueError('Texture path traverses outside the asset folder')
        return file.read_bytes()
    view = doc['bufferViews'][img['bufferView']]
    start = view.get('byteOffset', 0)
    return buffers[view['buffer']][start:start + view['byteLength']]


def build_atlas(doc, buffers, gltf_path, atlas_out, max_size=4096, tile_limit=256):
    """Pack glTF baseColor textures into one image with padded tiles.

    Returns map of glTF image indexes to (u, v, width, height) normalized tile
    rectangles. Index -1 is the neutral white tile, used for untextured meshes.
    """
    from PIL import Image, ImageOps
    used = set()
    for mesh, _ in iter_meshes(doc):
        for primitive in mesh['primitives']:
            mid = primitive.get('material', -1)
            mats = doc.get('materials', [])
            if not (0 <= mid < len(mats)): continue
            info = mats[mid].get('pbrMetallicRoughness', {}).get('baseColorTexture', {})
            texture_index = info.get('index')
            if texture_index is not None and texture_index < len(doc.get('textures', [])):
                source = doc['textures'][texture_index].get('source')
                if source is not None: used.add(source)
    # A 4096 atlas with 256px tiles fits 256 baseColor textures including white.
    # For larger scenes reduce the individual image footprint instead of dropping
    # materials without notice.
    count = len(used) + 1
    tile = tile_limit
    while ((max_size // tile) ** 2 < count) and tile > 32:
        tile //= 2
    if (max_size // tile) ** 2 < count:
        raise ValueError(f'Too many distinct textures ({count}) for a {max_size}px atlas')
    columns = min(max_size // tile, max(1, math.ceil(math.sqrt(count))))
    rows = math.ceil(count / columns)
    width, height = columns * tile, rows * tile
    atlas = Image.new('RGBA', (width, height), (255,255,255,255))
    padding = 2
    rects = {}
    errors = []
    order = [-1] + sorted(used)
    for index, image_id in enumerate(order):
        col, row = index % columns, index // columns
        left, top = col * tile + padding, row * tile + padding
        size = tile - 2 * padding
        if image_id == -1:
            tex = Image.new('RGBA', (size, size), (255,255,255,255))
        else:
            try:
                raw = image_bytes(doc, buffers, image_id, gltf_path.parent)
                with Image.open(BytesIO(raw)) as src:
                    src.load()
                    tex = src.convert('RGBA')
                tex.thumbnail((size, size), Image.Resampling.LANCZOS)
                if tex.size != (size, size):
                    # Keep source aspect ratio, avoiding unpredictable UV space.
                    tex = ImageOps.fit(tex, (size, size), method=Image.Resampling.LANCZOS)
            except (ValueError, KeyError, OSError) as exc:
                errors.append({'image':image_id, 'error':str(exc)})
                tex = Image.new('RGBA', (size, size), (255,255,255,255))
        atlas.paste(tex, (left, top))
        # Replicate edge pixels to avoid cross-tile bilinear bleed.
        atlas.paste(tex.crop((0,0,size,1)), (left, top-1))
        atlas.paste(tex.crop((0,size-1,size,size)), (left, top+size))
        atlas.paste(tex.crop((0,0,1,size)), (left-1, top))
        atlas.paste(tex.crop((size-1,0,size,size)), (left+size, top))
        rects[image_id] = (left / width, top / height, size / width, size / height)
    atlas_out.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(atlas_out, format='PNG', optimize=True)
    return rects, errors


def primitive_material(doc, prim):
    mats = doc.get('materials', [])
    mid = prim.get('material', -1)
    color = (0.65, 0.7, 0.7, 1.)
    tex_source = -1
    texcoord = 0
    offset, tex_scale, rotation = [0., 0.], [1., 1.], 0.
    if 0 <= mid < len(mats):
        pbr = mats[mid].get('pbrMetallicRoughness', {})
        color = tuple(float(x) for x in pbr.get('baseColorFactor', color))
        texinfo = pbr.get('baseColorTexture', {})
        if 'index' in texinfo:
            texture = doc.get('textures', [])[texinfo['index']]
            tex_source = texture.get('source', -1)
            texcoord = texinfo.get('texCoord', 0)
            ext = texinfo.get('extensions', {}).get('KHR_texture_transform', {})
            texcoord = ext.get('texCoord', texcoord)
            offset = ext.get('offset', offset)
            tex_scale = ext.get('scale', tex_scale)
            rotation = ext.get('rotation', rotation)
    return color, tex_source, texcoord, offset, tex_scale, rotation


def align_weapon(p, direction):
    if direction == 'x':
        return (p[2], p[1], -p[0])  # rotation +90 degrees about Y
    if direction == 'y':
        return (p[0], p[2], -p[1])  # rotation -90 degrees about X
    return p


def convert(source, output, scale, limit, center=True, texture_atlas=None, weapon_length=None, max_source_coordinate=None):
    doc, buffers = load_gltf(source)
    textured = texture_atlas is not None
    rects = {-1:(0.,0.,1.,1.)}
    atlas_errors = []
    if textured:
        rects, atlas_errors = build_atlas(doc,buffers,source,texture_atlas)
    if max_source_coordinate is not None and max_source_coordinate <= 0:
        raise ValueError('max_source_coordinate must be positive')
    raw_triangles = []
    unsupported = 0
    excluded_outlier_triangles = 0
    weapon_axis = None
    if weapon_length is not None:
        if weapon_length <= 0:
            raise ValueError('weapon_length must be positive')
        original_bounds = []
        for mesh, model in iter_meshes(doc):
            for primitive in mesh['primitives']:
                if 'POSITION' in primitive.get('attributes', {}):
                    positions = accessor_values(doc, buffers, primitive['attributes']['POSITION'])
                    original_bounds.extend(transform(model, xyz[:3]) for xyz in positions)
        if not original_bounds: raise ValueError('Weapon asset contains no vertices')
        spans = [max(x[axis] for x in original_bounds) - min(x[axis] for x in original_bounds) for axis in range(3)]
        weapon_axis = 'xyz'[spans.index(max(spans))]
        scale = weapon_length / max(spans)

    for mesh, matrix in iter_meshes(doc):
        for prim in mesh['primitives']:
            if prim.get('mode',4) != 4 or 'POSITION' not in prim.get('attributes', {}):
                unsupported += 1
                continue
            attrs = prim['attributes']
            position = accessor_values(doc,buffers,attrs['POSITION'])
            indices = [v[0] for v in accessor_values(doc,buffers,prim['indices'])] if 'indices' in prim else list(range(len(position)))
            color, tex_source, texcoord, texoffset, texscale, texrotate = primitive_material(doc,prim)
            uv_index = attrs.get(f'TEXCOORD_{texcoord}')
            uv_values = accessor_values(doc,buffers,uv_index) if textured and uv_index is not None else None
            if uv_values is None: tex_source = -1
            region = rects.get(tex_source,rects[-1])
            world = [align_weapon(transform(matrix,p[:3]),weapon_axis) for p in position]
            for i in range(0,len(indices)-2,3):
                if len(raw_triangles) >= limit:
                    raise ValueError(f'GLB has more than {limit} triangles; increase --max-triangles')
                tri_indices=indices[i:i+3]
                a,b,c=[world[j] for j in tri_indices]
                # The published Nuketown GLB includes enormous sky/environment
                # geometry (hundreds of millions of source units). Such triangles
                # break the floor/collision raster and make camera culling useless.
                # Opt-in scene-space cutoff: leave weapon models and ordinary
                # conversion untouched, and record every excluded triangle.
                if max_source_coordinate is not None and any(
                        not math.isfinite(n) or abs(n) > max_source_coordinate
                        for vertex in (a,b,c) for n in vertex):
                    excluded_outlier_triangles += 1
                    continue
                u=tuple(b[k]-a[k] for k in range(3))
                v=tuple(c[k]-a[k] for k in range(3))
                normal=normalize(cross(u,v))
                uv = []
                if textured:
                    for j in tri_indices:
                        x,y = uv_values[j][:2] if uv_values else (0.,0.)
                        rx = x*texscale[0]
                        ry = y*texscale[1]
                        uv.append((math.cos(texrotate)*rx - math.sin(texrotate)*ry + texoffset[0],
                                   math.sin(texrotate)*rx + math.cos(texrotate)*ry + texoffset[1]))
                raw_triangles.append(((a,b,c),normal,color,tuple(uv),region))
    if not raw_triangles:
        raise ValueError('No convertible triangles remain; check scene bounds and coordinate cutoff')
    if excluded_outlier_triangles and excluded_outlier_triangles > len(raw_triangles):
        raise ValueError('Over half of source geometry exceeded --max-source-coordinate; check scene scale')
    minp=[min(p[i] for tri,_,_,_,_ in raw_triangles for p in tri) for i in range(3)]
    maxp=[max(p[i] for tri,_,_,_,_ in raw_triangles for p in tri) for i in range(3)]
    offset=[(minp[0]+maxp[0])/2, ((minp[1]+maxp[1])/2 if weapon_length is not None else minp[1]), (minp[2]+maxp[2])/2] if center else [0,0,0]
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open('wb') as file:
        file.write((TEXTURED_MAGIC if textured else MAGIC) + struct.pack('<I',len(raw_triangles)*3))
        for verts,normal,color,uv,rect in raw_triangles:
            for vi,p in enumerate(verts):
                point=[(p[i]-offset[i])*scale for i in range(3)]
                if textured:
                    file.write(struct.pack('<16f',*point,*normal,*color,*uv[vi],*rect))
                else:
                    file.write(struct.pack('<10f',*point,*normal,*color))
    print(json.dumps({'source':str(source),'out':str(output),'triangles':len(raw_triangles),
                      'unhandled_primitives':unsupported,'source_bounds':[minp,maxp],
                      'output_bytes':output.stat().st_size,'scale':scale,
                      'weapon_alignment_axis':weapon_axis,'textured':textured,'atlas':str(texture_atlas) if textured else None,
                      'missing_textures':atlas_errors[:30],'missing_texture_count':len(atlas_errors),
                      'excluded_outlier_triangles':excluded_outlier_triangles,
                      'max_source_coordinate':max_source_coordinate},indent=2))

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('glb',type=Path)
    p.add_argument('--out',type=Path,default=Path('MerkOfDuty/Resources/MerkMap.meshbin'))
    p.add_argument('--scale',type=float,default=0.01)
    p.add_argument('--max-triangles',type=int,default=1_000_000)
    p.add_argument('--keep-origin',action='store_true')
    p.add_argument('--texture-atlas',type=Path,help='Write PNG atlas and MERKMAP2 UV vertices (requires Pillow)')
    p.add_argument('--weapon-length',type=float,help='Normalize model largest axis to meters and orient its longest axis as Z')
    p.add_argument('--max-source-coordinate',type=float,help='Exclude remote environment/sky triangles outside +/- this many source units')
    args=p.parse_args()
    convert(args.glb,args.out,args.scale,args.max_triangles,not args.keep_origin,args.texture_atlas,args.weapon_length,args.max_source_coordinate)

if __name__ == '__main__':main()
