
import sys
import re

def convert_tscn(in_file, out_file):
    with open(in_file, 'r') as f:
        lines = f.readlines()

    with open(out_file, 'w') as f:
        # Header
        header = lines[0].strip()
        header = header.replace('format=3', 'format=2')
        header = re.sub(r' uid="[^"]*"', '', header)
        f.write(header + '\n')

        # Resources
        resource_map = {}
        for i in range(1, len(lines)):
            line = lines[i].strip()
            if line.startswith('[ext_resource'):
                line = line.replace('Texture2D', 'Texture')
                uid_match = re.search(r' uid="([^"]*)"', line)
                if uid_match:
                    line = re.sub(r' uid="[^"]*"', '', line)
                
                id_match = re.search(r' id="([^"]*)"', line)
                if id_match:
                    old_id = id_match.group(1)
                    new_id = str(len(resource_map) + 1)
                    resource_map[old_id] = new_id
                    line = line.replace(f' id="{old_id}"', f' id={new_id}')
                
                f.write(line + '\n')
            elif line.startswith('[node'):
                f.write('\n' + line + '\n')
            elif line:
                # Properties
                for old_id, new_id in resource_map.items():
                    line = line.replace(f'ExtResource("{old_id}")', f'ExtResource( {new_id} )')
                
                line = line.replace('Sprite2D', 'Sprite')
                line = line.replace('theme_override_constants', 'custom_constants')
                line = line.replace('theme_override_font_sizes', 'custom_font_sizes')
                line = line.replace('horizontal_alignment', 'align')
                line = line.replace('vertical_alignment', 'valign')
                line = line.replace('Array[Texture2D]', 'Array')
                
                if 'layout_mode = 3' in line and 'anchors_preset = 0' in lines[i-1]:
                    lines[i-1] = lines[i-1].replace('anchors_preset = 0', 'anchor_right = 1.0\nanchor_bottom = 1.0')

                if 'layout_mode = 1' in line and 'anchors_preset = 15' in lines[i-1]:
                    lines[i-1] = lines[i-1].replace('anchors_preset = 15', 'anchor_right = 1.0\nanchor_bottom = 1.0')
                
                if 'layout_mode = 1' in line and 'anchors_preset = 8' in lines[i-1]:
                    lines[i-1] = lines[i-1].replace('anchors_preset = 8', 'anchor_left = 0.5\nanchor_top = 0.5\nanchor_right = 0.5\nanchor_bottom = 0.5')
                    line = line.replace('offset_left', 'margin_left')
                    line = line.replace('offset_top', 'margin_top')
                    line = line.replace('offset_right', 'margin_right')
                    line = line.replace('offset_bottom', 'margin_bottom')

                f.write(line + '\n')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python convert_tscn.py <file.tscn>")
        sys.exit(1)
    
    in_file = sys.argv[1]
    out_file = in_file + '.new'
    convert_tscn(in_file, out_file)
    # os.replace(out_file, in_file)
    print(f"Converted {in_file} to {out_file}")
