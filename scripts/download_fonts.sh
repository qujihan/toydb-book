#!/bin/bash
font_dir="${HOME}/.local/share/fonts"
mkdir -p ${font_dir}

# maple font
maple_verison="7.0"
maple_zip_file="maple.zip"
curl -Lo ${maple_zip_file} https://github.com/subframe7536/Maple-font/releases/download/v${maple_verison}/MapleMono-NF-CN-unhinted.zip &&
    unzip ${maple_zip_file} -d ${font_dir}

# Noto Sans CJK SC
noto_sans_cjk_sc_version="2.004"
sans_zip_file="sans.zip"
curl -Lo ${sans_zip_file} https://github.com/notofonts/noto-cjk/releases/download/Sans${noto_sans_cjk_sc_version}/00_NotoSansCJK.ttc.zip &&
    unzip ${sans_zip_file} -d ${font_dir}

# Note Serif CJK SC
noto_serif_cjk_sc_version="2.003"
serif_zip_file="serif.zip"
curl -Lo ${serif_zip_file} https://github.com/notofonts/noto-cjk/releases/download/Serif${noto_serif_cjk_sc_version}/01_NotoSerifCJK.ttc.zip &&
    unzip ${serif_zip_file} -d ${font_dir}


# 霞鹜文楷
lxgw_wenkai_version="1.511"
lxgw_wenkai_zip_file="lxgw_wenkai.zip"
curl -Lo ${lxgw_wenkai_zip_file} https://github.com/lxgw/LxgwWenKai/releases/download/v${lxgw_wenkai_version}/lxgw-wenkai-v${lxgw_wenkai_version}.zip &&
    unzip ${lxgw_wenkai_zip_file} -d ${font_dir}

# Lora
lora_version="3.005"
lora_zip_file="lora.zip"
curl -Lo ${lora_zip_file} https://github.com/cyrealtype/Lora-Cyrillic/releases/download/v${lora_version}/Lora-v${lora_version}.zip &&
    unzip ${lora_zip_file} -d ${font_dir}

typst fonts --variants