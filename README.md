# 115-strm
通过115网盘生成下载目录树，自动生成strm文件，使用alist的情况下，可添加到emby进行播放，并且支持将目录树导入到alist的索引数据库，目前只测试音乐、视频，其他多媒体格式应也是可以的<br><br>
由于115目录树没有定义文件和文件夹，脚本采用常见的文件格式来区分，如果你处理的格式比较特别，可在高级配置里面查看内置的文件格式和新增文件格式，新增了自动更新的脚本，方便更新strm，使用的覆盖，有时间再考虑做去除无效strm
# Docker版
https://github.com/uwang/115-strm
# 分享音乐
https://115.com/s/swhsphs33xj?password=0000#
音乐22万首14.39T音乐包1
访问码：0000

https://115.com/s/swhsphb33xj?password=0000#
音乐22万首14.39T音乐包2
访问码：0000

https://115.com/s/swhspho33xj?password=0000#
音乐22万首14.39T音乐包3
访问码：0000


# 测试环境
系统ubuntu20<br><br>
安装好python3、sqlite3<br><br>
执行需要sudo权限<br><br>
alistV3.39.1<br><br>
使用strm，alist需要关闭签名，如果你不使用strm，只是建立alist的搜索数据库，则不需要关闭签名<br><br>
关闭签名方法:在管理-设置-全局-关闭签名所有，在储存-挂载的储存-启用签名选择关闭<br><br>
emby版本： 4.9.0.30 测试版<br><br>
播放音乐，需要关闭音频转码，在设置-用户-编辑-如有必要，在媒体播放期间允许音频转码 <br><br>
# 生成文件的目录树
最好是将要处理的文件放在一个目录，生成教程<br><br>
https://115.com/115115/T496626.html<br><br>

下载后将目录树放到ubuntu的目录
# 脚本
最好在存放目录树的地方执行脚本
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/suixing8/115-strm/main/115-strm.sh)"
```
# 使用教程

1: 将目录树转换为目录文件<br><br>
2: 生成 .strm 文件<br><br>
3: 建立alist索引数据库<br><br>
4: 高级配置（处理非常见媒体文件时使用）<br><br>


![image](https://github.com/user-attachments/assets/d2f203ae-ba6d-4bec-a339-f142d2b28b86)
<br><br>
## 1: 将目录树转换为目录文件
可下载后上传到服务器后输入完整路劲，也可以生成后的文件放到有alist挂载的目录，输入alist的下载链接
1是必操作项，2或者3，根据自己的需求使用<br><br>
![image](https://github.com/user-attachments/assets/c833d6e2-a84d-4e10-9f95-793649a5cb74)


## 2: 生成 .strm 文件
输入 .strm 文件保存的路径<br><br>
![image](https://github.com/user-attachments/assets/e3a53987-e1db-45c3-930a-5c9f54847972)<br><br>

输入alist的ip地址+端口<br><br>
![image](https://github.com/user-attachments/assets/86c8cb82-c4ee-4fcb-893a-33ad43d4814e)<br><br>
请输入alist存储里对应的挂载路径信息<br><br>
![image](https://github.com/user-attachments/assets/045fb0d8-68ab-4c01-b296-af8355b15a98)<br><br>
请输入剔除选项（输入要剔除的目录层级数量，默认为2）多了或者少了，自己调整一下，下面会解释原理<br><br>
![image](https://github.com/user-attachments/assets/2604da02-0782-4853-a8e3-fd97d88033ce)<br><br>

剔除的目录层级的解释，目的就是为了生成的strm结构能和alist的结构一致，不想了解直接默认2，<br><br>
我贴出我的示例，我在115，长按电视剧文件夹，生成目录树，alist根文件夹ID，也是电视剧这个目录的id
![image](https://github.com/user-attachments/assets/7238a63c-f17b-475a-97c1-baaafa6ec20f)<br><br>

我在alist挂载的是/每日更新/电视剧/国产剧（115）这个目录<br><br>
![image](https://github.com/user-attachments/assets/0b951ba5-9a1c-45f2-94bc-34e61b5a351c)<br><br>

alist挂载是不显示目录的id的文件名的，所以直接显示115网盘电视剧目录下的文件<br><br>
![image](https://github.com/user-attachments/assets/2480984a-95ec-4eb6-87d1-96c343ee61c4)<br><br>


115目录树在生成的时候，会多自动多生成建立目录树文件的上一级目录
也就是我生成电视剧这个文件夹的目录树的时候，目录树会生成/我的资源/电视剧
所以115自动生成的目录树对于alist来说，多了2层目录，这种情况下，默认剔除2层目录，看不懂就多实践<br><br>

等待处理后，strm文件创建到此结束<br><br>
![image](https://github.com/user-attachments/assets/33688331-776d-4e6c-99e7-877498cb51cd)<br><br>
strm文件测试，随便打开一个strm文件，复制链接粘贴到浏览器打开，能下载就是没问题的<br><br>

![image](https://github.com/user-attachments/assets/dd9a8fd0-9b0e-4c75-ad6e-d217d27e4fc9)<br><br>


## 3: 建立alist索引数据库

alsit版本不能太低，最好在v3.37.x以后的版本,

如果你执行脚本的服务器和alist的服务器不在同一个系统，需要将alsit停止后，备份data.db数据库，将data.db数据库文件存放到脚本执行的目录<br><br>
如果你执行脚本的服务器和alist的服务器在同一个系统，需要将alsit停止后，备份data.db数据库，输入alist的数据路文件路劲就可以<br><br>

在主页面选择3<br><br>
脚本会自动获取当前的文件提供选择,剔除路径和新增路劲跟生成strm同理<br><br>
![image](https://github.com/user-attachments/assets/4db9147f-c17d-4911-9e0d-970813751e79)

<br><br>

根据实际情况选择替换还是新增到数据路的索引表，这个只会修改数据库的索引表，不会进行其他操作<br><br>

![image](https://github.com/user-attachments/assets/fe790ea3-9ea2-497d-b925-d93752e1e08f)


<br><br>
如果你执行脚本的服务器和alist的服务器不在同一个系统，需要执行多这一步，如果你第一步直接填写的alist数据库文件，不需要此步骤<br><br>
将data.db上传到alist目录，替换data.db，再次提醒data.db提前备份，<br><br>

![image](https://github.com/user-attachments/assets/47a876cb-9686-406a-a0fc-848488be1de7)<br><br>

在alist设置-索引，设置为数据库(非全文搜索)，点击保存就可以了
![image](https://github.com/user-attachments/assets/9823d5a7-ae6a-45ce-a91b-f2156b43904c)<br><br>

开启alist，以下为效果，理论上，你可以将整个115网盘都挂载到alist，并且在alist上就可以搜索和观看<br><br>

![image](https://github.com/user-attachments/assets/a38c96e5-f4fb-4790-9da9-b422bab1d5ee)<br><br>


如果你是苹果手机，推荐使用Fileball，使用alist添加后，不能是webdav的方式添加，添加后，选择搜索，全局搜索，可以直接调用alist的api进行搜索
这个比较适合看电影电视剧综艺，因为Fileball不支持音乐，这个是目前我所使用的众多app中，唯一一个支持调用alist搜索api的<br><br>

![4261a8529bb4f3a4083fb4e54eddbd1](https://github.com/user-attachments/assets/9d4f8d0e-51aa-40ae-9f2a-94200ac96aa9)<br><br>


# 最后，转发请注明出处
感谢ChatGPT-4o提供的代码<br><br>
感谢@uwang
联系https://t.me/gengpengw




