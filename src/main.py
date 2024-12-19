#!/usr/bin/env python3
# -*- coding:utf-8 -*-
import os
import urllib.parse
import requests
import chardet  # 用于检测文件编码
import json
from datetime import datetime
import hashlib

# 从环境变量获取配置
ALIST_HOST = os.getenv("ALIST_HOST", "127.0.0.1")
ALIST_PORT= os.getenv("ALIST_PORT", 5244)
ALIST_115_MOUNT_PATH = os.getenv("ALIST_115_MOUNT_PATH", "/115")
ALIST_115_TREE_FILE = os.getenv("ALIST_115_TREE_FILE", "/目录树.txt")
STRM_SAVE_PATH = os.getenv("STRM_SAVE_PATH", "/data")
EXCLUDE_OPTION = int(os.getenv("EXCLUDE_OPTION", 1))
UPDATE_EXISTING = int(os.getenv("UPDATE_EXISTING", 1)) # 默认更新已存在的 strm 文件
DELETE_ABSENT = int(os.getenv("DELETE_ABSENT", 1))     # 默认删除目录树中不存在的 strm 文件

ALIST_115_TREE_FILE_FOR_GUEST = os.getenv("ALIST_115_TREE_FILE_FOR_GUEST", "")

ALIST_URL = f"http://{ALIST_HOST}:{ALIST_PORT}"
ALIST_FILE_URL_PRFIX = f"{ALIST_URL}/d{ALIST_115_MOUNT_PATH}"
DIRECTORY_TREE_FILE = f"{ALIST_FILE_URL_PRFIX}{ALIST_115_TREE_FILE}"

# print(f"ALIST_URL: {ALIST_URL}")
# print(f"ALIST_FILE_URL_PRFIX: {ALIST_FILE_URL_PRFIX}")
# print(f"DIRECTORY_TREE_FILE: {DIRECTORY_TREE_FILE}")

def get_media_extensions():
    """
    从环境变量 MEDIA_EXTENSIONS 获取媒体扩展名集合。
    如果环境变量不存在或为空，使用默认值。
    """
    default_extensions = {
        "mp3", "flac", "wav", "aac", "ogg", "wma", "alac", "m4a",
        "aiff", "ape", "dsf", "dff", "wv", "pcm", "tta",
        "mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "vob", "mpg", "mpeg",
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "heic",
        "iso", "img", "bin", "nrg", "cue", "dvd",
        "lrc", "srt", "sub", "ssa", "ass", "vtt", "txt",
        "pdf", "doc", "docx", "csv", "xml", "new"
    }
    # 从环境变量中获取
    env_extensions = os.getenv("MEDIA_EXTENSIONS", "")
    if env_extensions:
        # 将环境变量中的逗号分隔的字符串转换为集合
        return set(ext.strip() for ext in env_extensions.split(",") if ext.strip())
    return default_extensions

def extract_filename_from_url(url):
    """
    从 URL 提取文件名。

    :param url: 文件的 URL
    :return: 提取的文件名
    """
    parsed_url = urllib.parse.urlparse(url)
    filename = os.path.basename(parsed_url.path)
    return filename

def get_file_sha1(file_path):
    """
    计算指定文件的 SHA1 哈希值。

    参数:
        file_path (str): 文件的路径。

    返回:
        str: 文件的 SHA1 哈希值。
    """
    sha1 = hashlib.sha1()  # 创建一个 SHA1 哈希对象
    try:
        with open(file_path, 'rb') as f:  # 以二进制模式打开文件
            while chunk := f.read(8192):  # 分块读取文件（8192字节/块）
                sha1.update(chunk)
        return sha1.hexdigest()  # 返回哈希值的十六进制表示
    except FileNotFoundError:
        print(f"文件不存在: {file_path}")
    except Exception as e:
        print(f"计算 SHA1 失败: {e}")
    return None

def fetch_file_info(api_url, file_path, page=1, per_page=0, refresh=True):
    """
    从指定 API 获取文件数据。

    参数:
        api_url (str): API 的 URL 地址。
        file_path (str): 需要获取的文件路径。
        page (int): 页码，默认值为 1。
        per_page (int): 每页数量，默认值为 0。
        refresh (bool): 是否刷新缓存，默认值为 True。

    返回:
        str: API 返回的响应文本。
    """
    payload = json.dumps({
        "path": file_path,
        "page": page,
        "per_page": per_page,
        "refresh": refresh
    })
    headers = {
        'Content-Type': 'application/json'
    }
    try:
        response = requests.post(api_url, headers=headers, data=payload)
        response.raise_for_status()  # 检查 HTTP 请求是否成功
        return response.json()  # 返回 JSON 格式的数据
    except requests.exceptions.RequestException as e:
        print(f"请求失败: {e}")
        return None
    
def extract_modified_and_sha1(response_data):
    """
    提取 modified 和 sha1 值，并格式化 modified。

    参数:
        response_data (dict): API 返回的数据。

    返回:
        tuple: 格式化后的 modified 和 sha1 值。
    """
    try:
        # 提取 modified 和 sha1
        modified = response_data['data']['modified']
        sha1 = response_data['data']['hash_info']['sha1'].lower()

        # 格式化 modified 为 YYYY-MM-DD HH:mm:ss
        modified_dt = datetime.fromisoformat(modified)
        formatted_modified = modified_dt.strftime("%Y-%m-%d %H:%M:%S")

        return formatted_modified, sha1
    except (KeyError, TypeError) as e:
        print(f"数据提取失败: {e}")
        return None, None

def download_with_redirects(url, output_file):
    """
    模拟 curl -L 功能，处理 302 跳转并下载文件。
    
    :param url: 文件下载 URL
    :param output_file: 保存文件的路径
    """
    print(f"下载目录树文件: {url}")
    try:
        # 设置请求头，模拟 curl 的行为
        headers = {
            "User-Agent": "curl/8.1.2",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "Accept": "*/*",
        }

        # 发送 GET 请求，自动处理 302 重定向
        response = requests.get(url, headers=headers, stream=True, allow_redirects=True)
        response.raise_for_status()  # 确保状态码为 200

        # 保存文件
        with open(output_file, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)

        print(f"文件已下载并保存到: {output_file}")
    except requests.exceptions.RequestException as e:
        print(f"下载失败: {e}")

def detect_file_encoding(file_path):
    with open(file_path, 'rb') as f:
        raw_data = f.read()
    result = chardet.detect(raw_data)
    return result['encoding']

def parse_directory_tree(file_path, generated_file):
    """解析目录树并生成新的目录文件"""
    current_path_stack = []
    encoding = detect_file_encoding(file_path)
    print(f"检测到目录树文件编码: {encoding}")
    with open(file_path, 'r', encoding=encoding) as file, open(generated_file, 'w', encoding='utf-8') as output_file:
        for line in file:
            line = line.lstrip('\ufeff').strip()
            line_depth = line.count('|')
            item_name = line.split('|-')[-1].strip()
            if not item_name:
                continue
            while len(current_path_stack) > line_depth:
                current_path_stack.pop()
            if len(current_path_stack) == line_depth:
                if current_path_stack:
                    current_path_stack.pop()
            current_path_stack.append(item_name)
            full_path = '/' + '/'.join(current_path_stack)
            output_file.write(full_path + '\n')

def generate_strm_files(directory_file, strm_path, alist_full_url, exclude_option):
    """生成 .strm 文件，同时记录生成的文件路径"""
    os.makedirs(strm_path, exist_ok=True)
    media_extensions = get_media_extensions() # 获取文件类型后缀集合
    generated_files = set()  # 用于记录新生成的文件路径

    with open(directory_file, 'r', encoding='utf-8') as file:
        for line in file:
            line = line.strip()
            if line.count('/') < exclude_option + 1:
                continue
            adjusted_path = '/'.join(line.split('/')[exclude_option + 1:])
            if adjusted_path.split('.')[-1].lower() in media_extensions:
                encoded_path = urllib.parse.quote(adjusted_path)
                full_url = f"{alist_full_url}/{encoded_path}"
                strm_file_path = os.path.join(strm_path, adjusted_path + '.strm')
                os.makedirs(os.path.dirname(strm_file_path), exist_ok=True)

                with open(strm_file_path, 'w', encoding='utf-8') as strm_file:
                    strm_file.write(full_url)

                # 记录生成的文件
                generated_files.add(os.path.abspath(strm_file_path))

    return generated_files


def delete_absent_files(strm_path, generated_files):
    """删除不存在于生成列表中的文件"""
    for root, _, files in os.walk(strm_path):
        for file in files:
            if file.endswith('.strm'):
                full_path = os.path.abspath(os.path.join(root, file))
                if full_path not in generated_files:
                    os.remove(full_path)
                    print(f"删除多余文件: {full_path}")

if __name__ == "__main__":
    # 检查目录树文件
    if DIRECTORY_TREE_FILE.startswith("http"):
        # 目录树文件为远端文件
        output_file = f"{STRM_SAVE_PATH}/{extract_filename_from_url(DIRECTORY_TREE_FILE)}"
        
        if ALIST_115_TREE_FILE_FOR_GUEST:
            # 如果设置了目录树探测路径，说明开启了此功能
            api_url_file_info = f"{ALIST_URL}/api/fs/get"
            response = fetch_file_info(api_url_file_info, ALIST_115_TREE_FILE_FOR_GUEST)
            if response:
                modified, sha1 = extract_modified_and_sha1(response)
                print(f"Modified: {modified} SHA1: {sha1}")
                if os.path.isfile(output_file) and sha1 == get_file_sha1(output_file):
                    # 判断本地文件 sha1 与远端是否相同
                    print(f"文件 hash 值未改变，更新跳过。")
                    exit(1)  # 退出程序，状态码为 1
                else:
                    download_with_redirects(DIRECTORY_TREE_FILE, output_file)
        else:
            download_with_redirects(DIRECTORY_TREE_FILE, output_file)
    else:
        # 目录树为本地文件
        output_file = DIRECTORY_TREE_FILE
    
    if not os.path.isfile(output_file):
        print(f"目录树文件不存在: {output_file}")
        exit(1)

    # 解析目录树文件
    converted_file = os.path.splitext(output_file)[0] + '_converted.txt'
    parse_directory_tree(output_file, converted_file)

    # 生成 .strm 文件
    generated_files = generate_strm_files(converted_file, STRM_SAVE_PATH, ALIST_FILE_URL_PRFIX, EXCLUDE_OPTION)

    # 删除多余的 .strm 文件
    if DELETE_ABSENT == 1:
        delete_absent_files(STRM_SAVE_PATH, generated_files)

    os.remove(converted_file)
    print(".strm 文件生成完成！")