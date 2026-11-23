#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成规则库热更清单。

用法（在仓库根执行）：
    python tools/build_rule_pack_manifest.py [--version N]

做三件事：
1. 从 assets/rule_packs/*.json 计算 sha256 与字节数；
2. 写入 assets/rule_packs/manifest.json（内置清单，随安装包发布）；
3. 同步一份到 rule_packs/（热更发布目录，push 后 GitHub raw 即生效）。

版本号规则：清单 version 严格递增才生效；缓存版本 <= 内置版本时以内置为准。
"""
import argparse
import hashlib
import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, 'assets', 'rule_packs')
PUBLISH = os.path.join(ROOT, 'rule_packs')
DATA_FILES = ['rule_packs.json', 'short_drama_packs.json']


def build(version):
    files = []
    for name in DATA_FILES:
        path = os.path.join(ASSETS, name)
        raw = open(path, 'rb').read()
        files.append({
            'file': name,
            'bytes': len(raw),
            'sha256': hashlib.sha256(raw).hexdigest(),
        })
    return {
        'schema': 1,
        'version': version,
        'builtAt': '2026-11-23',
        'files': files,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', type=int, default=2)
    args = parser.parse_args()

    data = build(args.version)
    text = json.dumps(data, ensure_ascii=False, indent=2) + '\n'

    os.makedirs(PUBLISH, exist_ok=True)
    with open(os.path.join(ASSETS, 'manifest.json'), 'w', encoding='utf-8') as f:
        f.write(text)
    with open(os.path.join(PUBLISH, 'manifest.json'), 'w', encoding='utf-8') as f:
        f.write(text)
    for name in DATA_FILES:
        shutil.copyfile(os.path.join(ASSETS, name), os.path.join(PUBLISH, name))

    print('manifest version =', args.version)
    for item in data['files']:
        print('  {file}  {bytes} bytes  {sha256}'.format(**item))


if __name__ == '__main__':
    main()
