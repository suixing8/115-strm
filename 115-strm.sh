#!/bin/bash

# 设置 UTF-8 环境，确保字符编码一致
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 配置文件路径，改用$HOME来确保路径正确解析
config_file="$HOME/.115-strm.conf"

# 读取配置文件函数
read_config() {
    if [ -f "$config_file" ]; then
        # shellcheck source=/dev/null
        . "$config_file"
    fi
    update_existing="${update_existing:-1}" # 默认值为 1（跳过）
    delete_absent="${delete_absent:-2}"     # 默认值为 2（不删除）
}

# 保存配置文件函数
save_config() {
    cat <<EOF >"$config_file"
directory_tree_file="$directory_tree_file"
strm_save_path="$strm_save_path"
alist_url="$alist_url"
mount_path="$mount_path"
exclude_option="$exclude_option"
custom_extensions="$custom_extensions"
update_existing="$update_existing"
delete_absent="$delete_absent"
EOF
}

# 检查是否安装了所需软件包或工具，若未安装则提示用户并退出
if ! command -v python3 &>/dev/null; then
    echo "Python 3 未安装，请安装后再运行此脚本。"
    exit 1
fi

# 检查是否安装了 iconv
if ! command -v iconv &>/dev/null; then
    echo "iconv 未安装，请安装后再运行此脚本。"
    exit 1
fi

# 检查是否安装了 sqlite3
if ! command -v sqlite3 &>/dev/null; then
    echo "sqlite3 未安装，请安装后再运行此脚本。"
    exit 1
fi

# 检查是否安装了 curl
if ! command -v curl &>/dev/null; then
    echo "curl 未安装，请安装后再运行此脚本。"
    exit 1
fi

# 初始化配置
read_config

# 显示主菜单的函数
show_menu() {
    echo "请选择操作："
    echo "1: 将目录树转换为目录文件"
    echo "2: 生成 .strm 文件"
    echo "3: 建立 alist 索引数据库"
    echo "4: 创建自动更新脚本"
    echo "5: 高级配置（处理非常见媒体文件时使用）"
    echo "6: 扫描并下载字幕文件"
    echo "0: 退出"
}


# 初始化全局变量，存储生成的目录文件路径和自定义扩展名
generated_directory_file="${generated_directory_file:-}"
custom_extensions="${custom_extensions:-}"

# 定义内置的媒体文件扩展名
builtin_audio_extensions=("mp3" "flac" "wav" "aac" "ogg" "wma" "alac" "m4a" "aiff" "ape" "dsf" "dff" "wv" "pcm" "tta")
builtin_video_extensions=("mp4" "mkv" "avi" "mov" "wmv" "flv" "webm" "vob" "mpg" "mpeg")
builtin_image_extensions=("jpg" "jpeg" "png" "gif" "bmp" "tiff" "svg" "heic")
builtin_other_extensions=("iso" "img" "bin" "nrg" "cue" "dvd" "lrc" "srt" "sub" "ssa" "ass" "vtt" "txt" "pdf" "doc" "docx" "csv" "xml" "new")

# 将目录树文件转换为目录文件的函数
convert_directory_tree() {
    if [ -n "$directory_tree_file" ]; then
        echo "请输入目录树文件的路径或者下载链接，上次配置:${directory_tree_file}，回车确认："
    else
        echo "请输入目录树文件的路径或者下载链接，路径示例：/path/to/alist20250101000000_目录树.txt，回车确认："
    fi
    read -r input_directory_tree_file
    directory_tree_file="${input_directory_tree_file:-$directory_tree_file}"

    if [[ $directory_tree_file == http* ]]; then
        url="$directory_tree_file"

        filename=$(basename "$url")
        decoded_filename=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$filename'))")

        # 下载文件
        curl -L -o "$filename" "$url"

        # 重命名文件
        mv "$filename" "$decoded_filename"

        # 更新 directory_tree_file 为新下载文件的完整路径
        directory_tree_file="$PWD/$decoded_filename"

        # 保存配置以记录新路径
        save_config
    fi

    if [ ! -f "$directory_tree_file" ]; then
        echo "目录树文件不存在，请提供有效的文件路径。"
        return
    fi

    # 获取目录树文件的目录和文件名
    directory_tree_dir=$(dirname "$directory_tree_file")
    directory_tree_base=$(basename "$directory_tree_file")

    # 转换目录树文件为 UTF-8 格式，以便处理（如有需要）
    converted_file="$directory_tree_dir/$directory_tree_base.converted"
    iconv -f utf-16le -t utf-8 "$directory_tree_file" >"$converted_file"

    # 生成的目录文件路径
    generated_directory_file="${converted_file}_目录文件.txt"

    # 使用 Python 解析目录树
    python3 - <<EOF
import os

def parse_directory_tree(file_path):
    current_path_stack = []
    directory_list_file = "${generated_directory_file}"

    # 打开输入文件和输出文件
    with open(file_path, 'r', encoding='utf-8') as file, \
         open(directory_list_file, 'w', encoding='utf-8') as output_file:
        for line in file:
            # 移除 BOM 和多余空白
            line = line.lstrip('\ufeff').rstrip()
            line_depth = line.count('|')  # 计算目录级别
            item_name = line.split('|-')[-1].strip()  # 获取当前项名称
            if not item_name:
                continue
            while len(current_path_stack) > line_depth:
                current_path_stack.pop()  # 移出多余的路径层级
            if len(current_path_stack) == line_depth:
                if current_path_stack:
                    current_path_stack.pop()
            current_path_stack.append(item_name)  # 添加当前项到路径栈
            full_path = '/' + '/'.join(current_path_stack)  # 构建完整路径
            output_file.write(full_path + '\n')  # 写入输出文件

parse_directory_tree("$converted_file")
EOF
    # 使用 sed 在 bash 中处理生成文件，替换每行开头的 "/|——" 为 "/"
    sed -i 's/^.\{4\}/\//' "${converted_file}_目录文件.txt"

    # 清理临时转换文件
    rm "$converted_file"
    echo "目录文件已生成：$generated_directory_file"

    # 保存配置
    save_config
}

# 自动查找可能的目录文件
find_possible_directory_file() {
    # 扫描当前目录中以 "_目录文件.txt" 结尾的文件
    possible_files=($(ls *_目录文件.txt 2>/dev/null | sort -V))

    if [ ${#possible_files[@]} -eq 0 ]; then
        echo "没有找到符合条件的目录文件。"
        return 1
    fi

    # 提供选择已找到的目录文件或输入完整路径
    echo "找到以下目录文件，请选择："
    select file in "${possible_files[@]}" "输入完整路径"; do
        case $file in
        "输入完整路径")
            echo "请输入目录文件的完整路径："
            read -r generated_directory_file
            if [ ! -f "$generated_directory_file" ]; then
                echo "文件不存在，请重新输入。"
                return 1
            fi
            break
            ;;
        *)
            generated_directory_file=$file
            break
            ;;
        esac
    done
}

# 生成 .strm 文件的函数
generate_strm_files() {
    # 检查是否已有生成的目录文件
    if [ -z "$generated_directory_file" ]; then
        if ! find_possible_directory_file; then
            return
        fi
    fi

    # 提示用户输入用于保存 .strm 文件的路径
    if [ -n "$strm_save_path" ]; then
        echo "请输入 .strm 文件保存的路径，上次配置:${strm_save_path}，回车确认："
    else
        echo "请输入 .strm 文件保存的路径："
    fi
    read -r input_strm_save_path
    strm_save_path="${input_strm_save_path:-$strm_save_path}"
    mkdir -p "$strm_save_path"

    # 提示用户输入 alist 的地址加端口
    if [ -n "$alist_url" ]; then
        echo "请输入alist的地址+端口（例如：http://abc.com:5244），上次配置:${alist_url}，回车确认："
    else
        echo "请输入alist的地址+端口（例如：http://abc.com:5244）："
    fi
    read -r input_alist_url
    alist_url="${input_alist_url:-$alist_url}"
    # 确保 URL 的格式正确，以 / 结尾
    if [[ "$alist_url" != */ ]]; then
        alist_url="$alist_url/"
    fi

    # 提示用户输入挂载路径信息
    decoded_mount_path=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('${mount_path}'))")
    if [ -n "$decoded_mount_path" ]; then
        echo "请输入alist存储里对应的挂载路径信息，上次配置:${decoded_mount_path}，回车确认："
    else
        echo "请输入alist存储里对应的挂载路径信息："
    fi
    read -r input_mount_path
    mount_path="${input_mount_path:-$mount_path}"

    # 处理挂载路径的不同输入情况
    if [[ "$mount_path" == "/" ]]; then
        mount_path=""
    elif [[ -n "$mount_path" ]]; then
        # 检查第一个字符是否是 /
        if [[ "${mount_path:0:1}" != "/" ]]; then
            mount_path="/${mount_path}"
        fi
        # 检查最后一个字符是否是 /
        if [[ "${mount_path: -1}" == "/" ]]; then
            mount_path="${mount_path%/}"
        fi
    fi

    # 编码挂载路径
    encoded_mount_path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${mount_path}'))")

    # 拼接 URL
    full_alist_url="${alist_url%/}/d${encoded_mount_path}/"

    # 提示用户输入剔除选项，增加默认值为2
    if [ -n "$exclude_option" ]; then
        echo "请输入剔除选项（输入要剔除的目录层级数量，默认为2），上次配置:${exclude_option}，回车确认："
    else
        echo "请输入剔除选项（输入要剔除的目录层级数量，默认为2）："
    fi
    read -r input_exclude_option
    exclude_option=${input_exclude_option:-2}

    # 提示选择更新该是跳过
    echo "如果本次要创建的strm文件已存在，请选择更新还是跳过（上次配置: ${update_existing:-1}）：1. 跳过 2. 更新"
    read -r input_update_existing
    update_existing="${input_update_existing:-$update_existing}"
    # 提示选择更新该是跳过
    echo "如果本次目录中存在本次未创建的strm文件，是否删除（上次配置: ${delete_absent:-2}）：1. 删除 2. 不删除"
    read -r input_delete_absent
    delete_absent="${input_delete_absent:-$delete_absent}"

    # 创建临时文件来存储现有的目录结构
    temp_existing_structure=$(mktemp)
    temp_new_structure=$(mktemp)

    # 获取现有的 .strm 文件目录结构并存入临时文件
    find "$strm_save_path" -type f -name "*.strm" >"$temp_existing_structure"

    # 使用 Python 生成 .strm 文件并处理多线程与进度显示
    python3 - <<EOF
import os
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading

# 定义一些变量
update_existing = $update_existing
delete_absent = $delete_absent


# 定义常见的媒体文件扩展名，并合并用户自定义扩展名
media_extensions = set([
    "mp3", "flac", "wav", "aac", "ogg", "wma", "alac", "m4a",
    "aiff", "ape", "dsf", "dff", "wv", "pcm", "tta",
    "mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "vob", "mpg", "mpeg",
    "jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "heic",
    "iso", "img", "bin", "nrg", "cue", "dvd",
    "lrc", "srt", "sub", "ssa", "ass", "vtt", "txt",
    "pdf", "doc", "docx", "csv", "xml", "new"
])
custom_extensions = set("${custom_extensions}".split())
media_extensions.update(custom_extensions)

# 设定变量
exclude_option = $exclude_option
alist_url = "$full_alist_url"
strm_save_path = "$strm_save_path"
generated_directory_file = "$generated_directory_file"

# 临时文件路径，存放在当前脚本执行目录
temp_existing_structure = os.path.join("${script_dir}", "existing_structure.txt")
temp_new_structure = os.path.join("${script_dir}", "new_structure.txt")
temp_to_create = os.path.join("${script_dir}", "to_create.txt")
temp_to_delete = os.path.join("${script_dir}", "to_delete.txt")

# 获取现有的 .strm 文件目录结构
def list_existing_files():
    existing_files = []
    for root, _, files in os.walk(strm_save_path):
        for file in files:
            if file.endswith('.strm'):
                existing_files.append(os.path.join(root, file))
    with open(temp_existing_structure, 'w', encoding='utf-8') as f:
        f.writelines(f"{line}\n" for line in existing_files)

# 处理生成目录结构
def process_directory_structure():
    with open(generated_directory_file, 'r', encoding='utf-8') as file, open(temp_new_structure, 'w', encoding='utf-8') as new_structure_file:
        for line in file:
            line = line.strip()
            if line.count('/') < exclude_option + 1:
                continue

            adjusted_path = '/'.join(line.split('/')[exclude_option + 1:])
            if adjusted_path.split('.')[-1].lower() in media_extensions:
                new_structure_file.write(adjusted_path + '\n')

# 根据文件列表创建或更新 .strm 文件
def create_strm_files():
    total = 0
    with open(temp_new_structure, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        total = len(lines)
    
    processed = 0
    lock = threading.Lock()
    with open(temp_to_create, 'w', encoding='utf-8') as to_create_file:
        def process_line(line):
            nonlocal processed
            line = line.strip()
            parent_path, file_name = os.path.split(line)
            strm_file_path = os.path.join(strm_save_path, parent_path, f"{file_name}.strm")
            os.makedirs(os.path.join(strm_save_path, parent_path), exist_ok=True)

            if not os.path.exists(strm_file_path) or update_existing == 2:
                encoded_path = urllib.parse.quote(line)
                with open(strm_file_path, 'w', encoding='utf-8') as strm_file:
                    strm_file.write(f"{alist_url}{encoded_path}")
                to_create_file.write(strm_file_path + '\n')

            with lock:
                processed += 1
                print(f"\r创建 .strm：{processed}/{total} ({processed / total:.2%})", end='')

        with ThreadPoolExecutor(max_workers=min(4, os.cpu_count() or 1)) as executor:
            futures = [executor.submit(process_line, line) for line in lines]
            for _ in as_completed(futures):
                pass

# 删除多余的 .strm 文件
def delete_obsolete_files():
    if delete_absent != 1:
        return

    with open(temp_existing_structure, 'r', encoding='utf-8') as existing_file:
        existing_files = set(existing_file.read().splitlines())
    with open(temp_new_structure, 'r', encoding='utf-8') as new_file:
        new_files = {os.path.join(strm_save_path, '/'.join(path.split('/')[:-1]), path.split('/')[-1] + '.strm') for path in new_file.read().splitlines()}
    
    files_to_delete = existing_files - new_files
    total = len(files_to_delete)
    processed = 0
    lock = threading.Lock()

    with open(temp_to_delete, 'w', encoding='utf-8') as to_delete_file:
        def process_deletion(file_path):
            nonlocal processed
            try:
                os.remove(file_path)
                to_delete_file.write(file_path + '\n')
                parent_dir = os.path.dirname(file_path)
                while parent_dir and parent_dir != strm_save_path:
                    try:
                        os.rmdir(parent_dir)
                    except OSError:
                        break
                    parent_dir = os.path.dirname(parent_dir)
            except OSError:
                pass

            with lock:
                processed += 1
                print(f"\r删除 .strm：{processed}/{total} ({processed / total:.2%})", end='')

        with ThreadPoolExecutor(max_workers=min(4, os.cpu_count() or 1)) as executor:
            futures = [executor.submit(process_deletion, file_path) for file_path in files_to_delete]
            for _ in as_completed(futures):
                pass

print("检测现有 .strm 文件...")
list_existing_files()

print("生成新的目录结构...")
process_directory_structure()

print("创建 .strm 文件...")
create_strm_files()

print("\n删除多余的 .strm 文件...")
delete_obsolete_files()

print("\n操作完成。")

EOF

    # 定义当前脚本的执行目录
    script_dir=$(pwd)

    # 清理临时文件
    for temp_file in "existing_structure.txt" "new_structure.txt" "to_create.txt" "to_delete.txt"; do
        temp_file_path="${script_dir}/${temp_file}"
        if [ -f "$temp_file_path" ]; then
            rm "$temp_file_path"
            echo "已删除临时文件：'$temp_file_path'"
        else
            echo "没有检测到需要删除的文件：'$temp_file_path'"
        fi
    done

    # 保存配置
    save_config
}
# 建立 alist 索引数据库的函数
build_index_database() {
    # 检查是否有生成的目录文件
    if [ -z "$generated_directory_file" ]; then
        if ! find_possible_directory_file; then
            return
        fi
    fi

    echo "建议备份后操作，请输入alist的data.db文件的完整路劲，上次配置:${db_file:-无}，回车确认"
    select input_db_file in *.db "输入完整路径"; do
        case $input_db_file in
        "输入完整路径")
            echo "请输入数据库文件的完整路径："
            read -r input_db_file
            if [ ! -f "$input_db_file" ]; then
                echo "文件不存在，请重新输入。"
                return
            fi
            break
            ;;
        *.db)
            db_file=$input_db_file
            break
            ;;
        *)
            echo "无效选择，请重试。"
            ;;
        esac
    done

    # 提示用户输入挂载路径信息
    decoded_mount_path=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('${mount_path}'))")
    if [ -n "$decoded_mount_path" ]; then
        echo "请输入alist存储里对应的挂载路径信息，上次配置:${decoded_mount_path}，回车确认："
    else
        echo "请输入alist存储里对应的挂载路径信息："
    fi
    read -r input_mount_path
    mount_path="${input_mount_path:-$mount_path}"

    # 检查挂载路径的有效性（必须以 / 开头）
    while [[ "$mount_path" != /* ]]; do
        echo "路径输入错误，请输入以 / 开头的完整路径："
        read -r mount_path
    done

    # 去除挂载路径末尾的斜杠（如果有），保障路径的一致性
    mount_path="${mount_path%/}"

    # 提示用户输入剔除选项，增加默认值为2
    if [ -n "$exclude_option" ]; then
        echo "请输入剔除选项（输入要剔除的目录层级数量，默认为2），上次配置:${exclude_option}，回车确认："
    else
        echo "请输入剔除选项（输入要剔除的目录层级数量，默认为2）："
    fi
    read -r input_exclude_option
    exclude_option=${input_exclude_option:-$exclude_option}

    # 创建临时数据库文件以存储处理结果
    temp_db_file=$(mktemp --suffix=.db)

    python3 - <<EOF
import sqlite3
import os
import time

# 设置变量
exclude_option = $exclude_option
generated_directory_file = "$generated_directory_file"
mount_path = "$mount_path"
temp_db_file = "$temp_db_file"

def is_directory(name):
    # 判断路径是否为文件夹
    return '.' not in name

# 将数据插入到临时数据库中
def insert_data_into_temp_db(file_path, db_path, exclude_level, mount_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 创建表结构
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS x_search_nodes (
        parent TEXT,
        name TEXT,
        is_dir INTEGER,
        size INTEGER
    )
    ''')

    with open(file_path, 'r', encoding='utf-8') as file:
        total_lines = sum(1 for _ in file)
        file.seek(0)
        valid_lines = total_lines - exclude_level
        processed_lines = 0
        start_time = time.time()

        for line in file:
            line = line.rstrip()
            path_parts = line.split('/')[exclude_level+1:]

            if len(path_parts) < 1:
                continue

            # 新增目录层级加到剔除目录层级后的信息前面
            parent = mount_path + '/' + '/'.join(path_parts[:-1])
            name = path_parts[-1]
            
            is_dir = 1 if is_directory(name) else 0

            # 插入数据到表中
            cursor.execute('INSERT INTO x_search_nodes (parent, name, is_dir, size) VALUES (?, ?, ?, 0)', (parent, name, is_dir))
            
            processed_lines += 1
            elapsed_time = time.time() - start_time
            minutes, seconds = divmod(int(elapsed_time), 60)
            progress_percentage = processed_lines / valid_lines if valid_lines else 0
            print(f"\r总文件：{total_lines}，剔除数：{exclude_level}，有效数：{valid_lines}，已处理：{processed_lines}，进度：{progress_percentage:.2%}，耗时：{minutes:02}:{seconds:02}", end='')

    print()  # 换行显示
    conn.commit()
    conn.close()

insert_data_into_temp_db(generated_directory_file, temp_db_file, exclude_option, mount_path)
EOF

    echo "数据已处理完毕。请选择操作："
    echo "1: 新增到现有数据库索引表，如果你数据库已经有索引信息，选择1"
    echo "2: 替换现有数据库索引表，如果你数据库已经没有索引信息，选择2"

    read -r db_choice

    # 根据选择执行相应操作
    case $db_choice in
    1)
        # 新增数据到数据库
        sqlite3 "$db_file" <<SQL
ATTACH DATABASE '$temp_db_file' AS tempdb;
INSERT INTO main.x_search_nodes (parent, name, is_dir, size)
SELECT parent, name, is_dir, size FROM tempdb.x_search_nodes;
DETACH DATABASE tempdb;

-- 去重逻辑
DELETE FROM x_search_nodes 
WHERE rowid NOT IN (
    SELECT MIN(rowid)
    FROM x_search_nodes
    GROUP BY parent, name
);
SQL
        ;;
    2)
        # 替换数据库表数据
        sqlite3 "$db_file" <<SQL
DELETE FROM x_search_nodes;
ATTACH DATABASE '$temp_db_file' AS tempdb;
INSERT INTO main.x_search_nodes (parent, name, is_dir, size)
SELECT parent, name, is_dir, size FROM tempdb.x_search_nodes;
DETACH DATABASE tempdb;
SQL
        ;;
    *)
        echo "无效的选项，操作已取消。"
        rm "$temp_db_file"
        return
        ;;
    esac

    # 在数据库中创建索引
    sqlite3 "$db_file" <<SQL
CREATE INDEX IF NOT EXISTS idx_x_search_nodes_parent ON x_search_nodes (parent);
SQL

    # 删除临时数据库文件
    rm "$temp_db_file"
    echo "操作完成，索引已更新。"

    # 保存配置
    save_config
}

# 打印内置格式的函数
print_builtin_formats() {
    echo "内置的媒体文件格式如下："
    echo "音频格式: ${builtin_audio_extensions[*]// /、}"
    echo "视频格式: ${builtin_video_extensions[*]// /、}"
    echo "图片格式: ${builtin_image_extensions[*]// /、}"
    echo "其他格式: ${builtin_other_extensions[*]// /、}"
}

#自动更新脚本
create_auto_update_script() {
    echo "该功能的实现，需要在每次更新时，在115手动生成目录树，并且重命名为固定的文件名，再将目录树文件移动到，挂载到alist的115目录，让脚本可以通过alist下载到目录树文件"
    echo "比如我将挂载115的目录/影视 挂载到alist，那我生成目录树后，就放到/影视 的目录或者子目录都可以，或者你也可以存放到其他平台，前提条件是下载链接要固定。"
    echo "因为脚本要获取到你在115生成的目录树，才能进行更新strm文件和alist数据库，你现在可以生成一个目录树，并且重命名，可以使用目录树.txt，以后生成的都要命名为这个。"
    echo "目前只支持strm自动更新，2和3待开发，自动更新脚本手动执行报错的话，加上sudo"

    echo "1: 创建strm文件更新脚本"
    echo "2: alist数据库更新脚本"
    echo "3: 创建strm文件+alist数据库更新脚本"
    echo "0: 返回主菜单"

    read -r script_choice
    case $script_choice in
    1)
        echo "请输入脚本存放目录："
        read -r script_dir

        mkdir -p "$script_dir"

        if [ -n "$directory_tree_file" ]; then
            echo "请输入目录树文件的路径或者下载链接，上次配置:${directory_tree_file}，回车确认："
        else
            echo "请输入目录树下载的链接（路径示例：http://127.0.0.1:5244/d/115/目录树.txt），在alist找到创建的目录树文件，右击复制链接，回车确认："
        fi
        read -r download_link
        download_link="${download_link:-$directory_tree_file}"

        echo "请输入 .strm 文件保存的路径，上次配置:${strm_save_path}，回车确认："
        read -r input_strm_save_path
        strm_save_path="${input_strm_save_path:-$strm_save_path}"
        mkdir -p "$strm_save_path"

        echo "请输入alist的地址+端口（例如：http://abc.com:5244），上次配置:${alist_url}，回车确认："
        read -r input_alist_url
        alist_url="${input_alist_url:-$alist_url}"
        if [[ "$alist_url" != */ ]]; then
            alist_url="$alist_url/"
        fi
        echo -e "完成的 alist_url 为 ${alist_url}\n"

        echo "请输入alist存储里对应的挂载路径信息，上次配置:${mount_path}，回车确认："
        read -r input_mount_path
        mount_path="${input_mount_path:-$mount_path}"
        if [[ "$mount_path" == "/" ]]; then
            mount_path=""
        else
            mount_path="/${mount_path#/}"
            mount_path="${mount_path%/}"
        fi

        echo "请输入剔除选项（输入要剔除的目录层级数量，默认为2），上次配置:${exclude_option}，回车确认："
        read -r input_exclude_option
        exclude_option="${input_exclude_option:-$exclude_option}"

        # 定义脚本内容
        script_content="#!/bin/bash
# 下载目录树文件
curl -L -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \"$download_link?\$(date +%s)\" -o \"$script_dir/目录树.txt\"

# 转换目录树为目录文件并生成 .strm 文件
python3 -c \"
import os
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed

def parse_directory_tree(file_path):
    current_path_stack = []
    directory_list_file = '$script_dir/目录文件.txt'

    with open(file_path, 'rb') as file, open(directory_list_file, 'w', encoding='utf-8') as output_file:
        content = file.read()
        try:
            content = content.decode('utf-16')
        except UnicodeDecodeError:
            content = content.decode('utf-8', errors='ignore')

        for line in content.splitlines():
            line = line.lstrip('\ufeff').rstrip()
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
            output_file.write(full_path + '\\n')

# 处理每一行并生成 .strm 文件
def process_line(line, media_extensions, exclude_option, alist_url, mount_path, strm_save_path):
    line = line.rstrip()
    line_depth = line.count('/')
    if line_depth < exclude_option:
        return
    adjusted_path = '/'.join(line.split('/')[exclude_option:])
    if not adjusted_path:
        return
    file_extension = adjusted_path.split('.')[-1].lower()
    if file_extension not in media_extensions:
        return
    file_name = os.path.basename(adjusted_path)
    parent_path = os.path.dirname(adjusted_path)
    os.makedirs(os.path.join(strm_save_path, parent_path), exist_ok=True)
    
    encoded_path = urllib.parse.quote(f'd{mount_path}/{parent_path}/{file_name}')
    strm_file_path = os.path.join(strm_save_path, parent_path, f'{file_name}.strm')
    with open(strm_file_path, 'w', encoding='utf-8') as strm_file:
        strm_file.write(f'{alist_url}{encoded_path}')

# 创建 .strm 文件，使用多线程以提高效率
def create_strm_files():
    with open('$script_dir/目录文件.txt', 'r', encoding='utf-8') as file:
        lines = file.readlines()

    media_extensions = {
        'mp3', 'flac', 'wav', 'aac', 'ogg', 'wma', 'alac', 'm4a',
        'aiff', 'ape', 'dsf', 'dff', 'wv', 'pcm', 'tta',
        'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'vob', 'mpg', 'mpeg',
        'jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'svg', 'heic',
        'iso', 'img', 'bin', 'nrg', 'cue', 'dvd',
        'lrc', 'srt', 'sub', 'ssa', 'ass', 'vtt', 'txt',
        'pdf', 'doc', 'docx', 'csv', 'xml', 'new'
    }

    custom_extensions = set('$custom_extensions'.split())
    media_extensions.update(custom_extensions)

    exclude_option = $exclude_option + 1  # 增加一层
    alist_url = '$alist_url'
    mount_path = '$mount_path'
    strm_save_path = '$strm_save_path'

    # 使用线程池来并行化 .strm 文件的生成
    max_workers = min(4, os.cpu_count() or 1)
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(
                process_line, line, media_extensions, exclude_option, 
                alist_url, mount_path, strm_save_path
            ) 
            for line in lines
        ]
        # 确保所有任务完成
        for _ in as_completed(futures):
            pass

# 解析目录树并创建 .strm 文件
parse_directory_tree('$script_dir/目录树.txt')
create_strm_files()
\"

echo \"strm文件已更新。\"
"
        script_name="update-115-strm.sh"
        echo "$script_content" >"$script_dir/$script_name"

        chmod +x "$script_dir/$script_name"
        echo "自动更新脚本 $script_dir/$script_name 已生成，请添加到任务计划，可配置定时执行，在执行前，记得先到115生成目录树。"

        # 保存配置以记录新路径
        directory_tree_file="$download_link"
        save_config
        echo -e "\n配置文件已存储："
        cat $config_file
        echo -e "\n"
        ;;
    2)
        echo "功能待实现。"
        ;;
    3)
        echo "功能待实现。"
        ;;
    0)
        echo "返回主菜单。"
        ;;
    *)
        echo "无效的选项，请输入 0、1、2 或 3。"
        ;;
    esac
}
# 高级配置函数
advanced_configuration() {
    echo "由于115目录树没有对文件和文件夹进行定义，本脚本内置了常用文件格式进行文件和文件夹的判断。"
    echo "如果你处理的文件格式不常见，你可以在这里添加，多个格式请使用空格分隔，不需要一个个对，脚本自动会去重，例如：mp3 mp4"
    echo "退回主菜单请输入0，打印脚本内置格式请输入1。"
    read -r user_input

    if [[ "$user_input" == "0" ]]; then
        return
    elif [[ "$user_input" == "1" ]]; then
        print_builtin_formats
        return
    fi

    # 转换为小写并去重
    new_extensions=$(echo "$user_input" | tr ' ' '\n' | tr '[:upper:]' '[:lower:]' | sort -u)

    # 更新全局变量
    for ext in $new_extensions; do
        if ! echo "$custom_extensions" | grep -qw "$ext"; then
            custom_extensions="$custom_extensions $ext"
        fi
    done

    echo "已添加的自定义扩展名：$custom_extensions"

    # 保存配置
    save_config
}
# 高级配置函数
advanced_configuration() {
    echo "由于115目录树没有对文件和文件夹进行定义，本脚本内置了常用文件格式进行文件和文件夹的判断。"
    echo "如果你处理的文件格式不常见，你可以在这里添加，多个格式请使用空格分隔，不需要一个个对，脚本自动会去重，例如：mp3 mp4"
    echo "退回主菜单请输入0，打印脚本内置格式请输入1。"
    read -r user_input

    if [[ "$user_input" == "0" ]]; then
        return
    elif [[ "$user_input" == "1" ]]; then
        print_builtin_formats
        return
    fi

    # 转换为小写并去重
    new_extensions=$(echo "$user_input" | tr ' ' '\n' | tr '[:upper:]' '[:lower:]' | sort -u)

    # 更新全局变量
    for ext in $new_extensions; do
        if ! echo "$custom_extensions" | grep -qw "$ext"; then
            custom_extensions="$custom_extensions $ext"
        fi
    done

    echo "已添加的自定义扩展名：$custom_extensions"

    # 保存配置
    save_config
}

# 下载用户指定格式文件的函数
download_specified_files() {
    echo "请输入 .strm 文件所在目录路径（例如：/path/to/strm/files）："
    read -r strm_directory
    while [ ! -d "$strm_directory" ]; do
        echo "路径无效，请重新输入有效路径（必须是存在的目录）："
        read -r strm_directory
    done

    echo "如果不间隔时间可能引起风控，请输入每个文件下载之间的间隔时间（秒），默认为 3 秒："
    read -r interval_time
    interval_time="${interval_time:-3}"

    echo "请输入要处理的文件格式，使用空格分隔（例如：ass srt sub jpg）："
    read -r user_formats

    # 将用户输入的格式转换为小写并存入数组
    IFS=' ' read -r -a specified_formats <<< "$(echo "$user_formats" | tr '[:upper:]' '[:lower:]')"

    temp_download_list=$(mktemp)

    echo "正在扫描目录 $strm_directory 中的指定文件格式 .strm..."
    find "$strm_directory" -type f -name "*.strm" >"$temp_download_list"

    total_files=$(wc -l <"$temp_download_list")
    if [ "$total_files" -eq 0 ]; then
        echo "目录中没有发现任何指定格式的 .strm，请检查路径或文件内容。"
        rm "$temp_download_list"
        return
    fi

    # 下载指定格式的文件
    downloaded_count=0
    while IFS= read -r strm_file; do
        # 检查文件是否为用户指定的格式
        url=$(cat "$strm_file")
        file_extension=$(basename "$url" | awk -F. '{print tolower($NF)}')

        if [[ " ${specified_formats[*]} " == *" $file_extension "* ]]; then
            target_dir=$(dirname "$strm_file")
            original_filename=$(basename "$strm_file" .strm)
            target_file="$target_dir/$original_filename"

            echo "正在下载文件：$url"
            curl -L -o "$target_file" "$url"

            if [ $? -eq 0 ]; then
                echo "文件下载完成：$target_file"
                rm "$strm_file"
                echo "已删除对应的 .strm 文件：$strm_file"
                downloaded_count=$((downloaded_count + 1))
            else
                echo "文件下载失败：$url"
            fi

            # 等待设定的间隔时间
            sleep "$interval_time"
        else
            echo "跳过非指定格式文件：$strm_file"
        fi
    done <"$temp_download_list"

    echo "文件下载完成，共处理 $total_files 个 .strm 文件，成功下载 $downloaded_count 个文件。"
    rm "$temp_download_list"
}

# 显示主菜单的函数
show_menu() {
    echo "请选择操作："
    echo "1: 将目录树转换为目录文件"
    echo "2: 生成 .strm 文件"
    echo "3: 建立 alist 索引数据库"
    echo "4: 创建自动更新脚本"
    echo "5: 高级配置（处理非常见媒体文件时使用）"
    echo "6: 扫描并下载指定格式文件"
    echo "0: 退出"
}

# 主循环，持续显示菜单并处理用户输入
while true; do
    show_menu
    # 读取用户选择
    read -r choice
    case $choice in
    1)
        # 选择1：将目录树转换为目录文件
        convert_directory_tree
        ;;
    2)
        # 选择2：生成 .strm 文件
        generate_strm_files
        ;;
    3)
        # 选择3：建立 alist 索引数据库
        build_index_database
        ;;
    4)
        # 选择4：创建自动更新脚本
        create_auto_update_script
        ;;
    5)
        # 选择5：进行高级配置，添加非标准文件格式
        advanced_configuration
        ;;
    6)
        # 选择6：扫描并下载指定格式文件
        download_specified_files
        ;;
    0)
        # 选择0：退出程序
        echo "退出程序。"
        break
        ;;
    *)
        # 处理无效输入
        echo "无效的选项，请输入 0、1、2、3、4、5 或 6。"
        ;;
    esac
done
