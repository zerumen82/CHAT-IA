#!/usr/bin/env python3
"""
Generador de icono retro capsule para LightChat - Pill Software
Version con ICO properly formato
"""

from PIL import Image, ImageDraw
import struct
import io
import os

def create_capsule_image(size):
    """Crear imagen de capsula retro"""
    
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Colores
    primary = (15, 23, 42)
    secondary = (233, 69, 96)
    highlight = (255, 255, 255)
    shadow = (10, 15, 30)
    
    # Dimensiones
    margin = max(2, size // 8)
    capsule_width = size - (margin * 2)
    capsule_height = int(capsule_width * 2)
    
    if capsule_height > size - margin * 2:
        capsule_height = size - margin * 2
        capsule_width = int(capsule_height / 1.8)
    
    x1 = (size - capsule_width) // 2
    y1 = (size - capsule_height) // 2
    x2 = x1 + capsule_width
    y2 = y1 + capsule_height
    radius = capsule_width // 2
    
    # Sombra
    shadow_off = max(1, size // 32)
    draw.rounded_rectangle([x1+shadow_off, y1+shadow_off, x2+shadow_off, y2+shadow_off], radius=radius, fill=shadow)
    
    # Fondo
    draw.rounded_rectangle([x1, y1, x2, y2], radius=radius, fill=primary)
    
    # Mitad superior
    draw.ellipse([x1, y1, x1+capsule_width, y1+capsule_width], fill=secondary)
    
    # Mitad inferior  
    draw.ellipse([x1, y2-capsule_width, x2, y2], fill=primary)
    
    # Linea divisoria
    mid_y = y1 + capsule_height // 2
    line_w = max(1, size // 32)
    draw.line([x1+margin, mid_y, x2-margin, mid_y], fill=highlight, width=line_w)
    
    # Brillo
    hl_size = max(3, size // 6)
    draw.ellipse([x1+margin, y1+margin, x1+margin+hl_size, y1+margin+hl_size], fill=(255,255,255,120))
    hl2_size = max(2, size // 10)
    draw.ellipse([x2-margin-hl2_size, y1+capsule_height//3, x2-margin, y1+capsule_height//3+hl2_size], fill=(255,255,255,80))
    
    return img

def create_png_ico(png_path, ico_path):
    """Create ICO from PNG with multiple sizes"""
    
    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = []
    
    for s in sizes:
        images.append(create_capsule_image(s))
    
    # Save as ICO using PNG format (more compatible)
    images[0].save(
        ico_path,
        format='PNG',
        sizes=[(s, s) for s in sizes],
        append_images=images[1:]
    )
    
    print(f"Created: {ico_path}")

def create_proper_ico(sizes, output_path):
    """Create proper Windows ICO with PNG data embedded"""
    
    # Create PNG data for each size
    png_data_list = []
    for size in sizes:
        img = create_capsule_image(size)
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        png_data_list.append((size, buf.getvalue()))
    
    # ICO file format
    with open(output_path, 'wb') as f:
        # ICO header
        f.write(struct.pack('<HHH', 0, 1, len(sizes)))  # Reserved, Type (1=ICO), Count
        
        # Calculate offsets
        header_size = 6 + 16 * len(sizes)
        offset = header_size
        
        # Directory entries
        entries = []
        for i, (size, png_data) in enumerate(png_data_list):
            w = 0 if size >= 256 else size
            h = 0 if size >= 256 else size
            entry = struct.pack('<BBBBHHII',
                w,           # Width
                h,           # Height
                0,           # Color palette
                0,           # Reserved
                1,           # Color planes
                32,          # Bits per pixel
                len(png_data),  # Size of image data
                offset       # Offset to image data
            )
            f.write(entry)
            offset += len(png_data)
        
        # Image data
        for size, png_data in png_data_list:
            f.write(png_data)

if __name__ == '__main__':
    output_path = 'windows/runner/resources/app_icon.ico'
    
    # Create proper ICO
    create_proper_ico([16, 24, 32, 48, 64, 128, 256], output_path)
    
    file_size = os.path.getsize(output_path)
    print(f"Icono creado: {output_path}")
    print(f"Tamano: {file_size} bytes")
    
    # Also save preview
    img256 = create_capsule_image(256)
    img256.save(output_path.replace('.ico', '_256.png'))
    print("Vista previa guardada")
