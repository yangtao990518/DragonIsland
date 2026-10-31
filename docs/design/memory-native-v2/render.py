from pathlib import Path
import base64

OUT=Path(__file__).resolve().parent
ROOT=next(p for p in OUT.parents if (p/"project.yml").exists())
avatar=base64.b64encode((ROOT/'docs/design/memory-context-a-subpages/avatar-reference.png').read_bytes()).decode()

def icon(kind):
    paths={
      'book':'M4 4h7a3 3 0 0 1 3 3v14a4 4 0 0 0-4-2H4z M14 7a3 3 0 0 1 3-3h5v15h-4a4 4 0 0 0-4 2',
      'check':'m6 13 4 4 10-11 M22 13v8H3V3h12',
      'tray':'M6 4h14l4 13v5H2v-5z M2 17h7l2 3h4l2-3h7',
      'search':'M17 17 23 23 M20 11a9 9 0 1 1-18 0 9 9 0 0 1 18 0',
      'edit':'m5 18-1 5 5-1L23 8l-4-4z M16 7l4 4',
      'share':'M13 17V2 m-4 4 4-4 4 4 M7 9H3v15h20V9h-4',
    }
    return '<svg viewBox="0 0 26 26" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"><path d="'+paths[kind]+'"/></svg>'

def cell(title,value='',kind=None,tail='chevron',extra=''):
    mark='<span class="rowicon">'+icon(kind)+'</span>' if kind else ''
    end='<span class="chevron">›</span>' if tail=='chevron' else '<i class="switch"></i>' if tail=='toggle' else '<span class="tick">✓</span>' if tail=='check' else ''
    return '<div class="cell '+extra+'">'+mark+'<span class="celltitle">'+title+'</span>'+('<span class="value">'+value+'</span>' if value else '')+end+'</div>'

def group(content):return '<div class="group">'+content+'</div>'
def label(text):return '<div class="sectionlabel">'+text+'</div>'
def note(text):return '<p class="footnote">'+text+'</p>'
def nav(title,back='记忆与上下文',edit=False):
    if edit:return '<nav class="editnav"><span>取消</span><b>'+title+'</b><strong>保存</strong></nav>'
    return '<nav><span class="back">‹ <small>'+back+'</small></span><b>'+title+'</b><span class="navmore">···</span></nav>'
def screen(body,top,title='',bottom=''):
    return '<div class="screen"><div class="status"><b>9:41</b><span class="indicators"><i></i><svg viewBox="0 0 20 16"><path d="M2 6 Q10 -1 18 6 M5 9 Q10 5 15 9 M8 12 Q10 10 12 12"/></svg><b class="battery"></b></span></div>'+top+'<div class="content">'+body+'</div>'+('<div class="bottomtools">'+bottom+'</div>' if bottom else '')+'<div class="home"></div></div>'

def overview():
    title='<h1>记忆与上下文</h1><div class="scope"><img src="data:image/png;base64,'+avatar+'"><span>大肥鱼</span><small>独立保存</small></div>'
    content=title+label('内容')+group(cell('每日日记','18篇','book')+cell('事实与约定','12条','check')+cell('待确认记忆','3','tray',extra='pending'))
    content+=label('聊天时使用')+group(cell('记忆选择','自动检索')+cell('最近聊天','10轮')+cell('上下文预算','32K token'))
    content+=note('本次预计输入12K，回复预留4K。模型容量1M token。')
    content+=label('自动整理')+group(cell('每日整理',tail='toggle')+cell('整理时间','23:30'))
    content+=note('使用角色现有AI接口整理。到点未运行时，下次打开补齐。')
    content+=group(cell('查看下次携带内容',extra='accentrow'))
    return screen(content,nav('',back='聊天设置'))

def entry(day,title,excerpt,size,first=False):
    return '<div class="entry'+(' first' if first else '')+'"><div class="entrytop"><b>'+day+'</b><span>'+size+' KB</span><i>›</i></div><h3>'+title+'</h3><p>'+excerpt+'</p></div>'

def diary():
    content='<h1>每日日记</h1><div class="search">'+icon('search')+'<span>搜索日记</span></div>'
    content+='<div class="month"><span>2026年10月</span><small>大肥鱼</small></div>'
    content+='<div class="diaryentries">'+entry('今天 · 10月31日','聊天与记忆的新方案','讨论怎样保存和找回以前的聊天。','1.8',True)+entry('昨天 · 10月30日','主页布局与安装','确认按钮样式，记录安装反馈。','2.4')+entry('10月29日','灵动岛舞蹈测试','保留完整时序，等待手机体验。','1.2')+entry('10月28日','日常聊天与约定','记录今天聊过的事和明确的约定。','1.6')+'</div>'
    content+=note('每天一个文件，聊天时仅检索相关段落。')
    content+='<div class="lastupdate"><i></i><span>今天 19:25 已整理</span><b>重新整理</b></div>'
    return screen(content,nav(''),bottom='<span>'+icon('book')+'</span><small>18篇日记</small><span>'+icon('edit')+'</span>')

def editor():
    content=label('标题')+group('<div class="textinput">交流偏好</div>')
    content+=label('内容')+group('<div class="texteditor">希望回复自然，先说重点。重要的事情先确认，不替我自行决定。</div>')
    content+=label('聊天如何使用')+group(cell('始终携带',tail='none')+cell('按需检索',tail='check')+cell('停用',tail='none'))
    content+=note('按需检索：与当前问题相关时，再加入上下文。')
    content+=label('来源')+group(cell('10月31日 · 私聊','查看原话'))
    content+=note('仅用于大肥鱼的聊天。文件大小 428 B。')
    content+=group('<div class="cell delete">删除这条记忆</div>')
    return screen(content,nav('编辑记忆',edit=True))

CSS='''
*{box-sizing:border-box}html,body{margin:0;background:#e7e7eb;font-family:"Segoe UI","DengXian","Microsoft YaHei UI",sans-serif;color:#171719}body{width:1263px;padding:22px 24px 16px}button{font:inherit}h1,h2,h3,p{margin:0}b,strong{font-weight:600}.heading{display:flex;justify-content:space-between;align-items:center;margin:0 4px 18px}.heading>div{display:flex;align-items:baseline;gap:16px}.heading b{font-size:20px}.heading span,.heading small{font-size:12px;color:#88878c;font-weight:400}.boards{display:grid;grid-template-columns:repeat(3,393px);gap:18px}.pagelabel{margin:0 4px 9px;font-size:12px;color:#89878f}.screen{background:var(--background);border:1px solid #d9d9df;border-radius:30px;height:956px;overflow:hidden;display:flex;flex-direction:column;position:relative}.status{height:44px;min-height:44px;display:flex;align-items:center;justify-content:space-between;padding:0 29px;font-size:15px}.indicators{display:flex;align-items:center;gap:6px}.indicators>i{width:17px;height:12px;background:linear-gradient(to right,#171719 0 18%,transparent 18% 27%,#171719 27% 45%,transparent 45% 54%,#171719 54% 72%,transparent 72% 81%,#171719 81%);clip-path:polygon(0 100%,0 75%,18% 75%,18% 55%,45% 55%,45% 30%,72% 30%,72% 0,100% 0,100% 100%)}.indicators>svg{width:18px;height:15px;fill:none;stroke:#171719;stroke-width:2.5;stroke-linecap:round}.battery{width:24px;height:12px;border:1px solid #999;border-radius:3px;position:relative;padding:1px;display:block}.battery:before{content:"";display:block;height:100%;width:85%;background:#171719;border-radius:1px}.battery:after{content:"";position:absolute;right:-3px;top:3px;width:2px;height:4px;border-radius:0 2px 2px 0;background:#999}nav{height:43px;min-height:43px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;color:var(--accent);position:relative}nav>.back{font-size:31px;font-weight:300;display:flex;gap:5px;align-items:center;line-height:1}nav small{font-size:15px;font-weight:400}nav>b{font-size:17px;color:#171719;position:absolute;left:50%;transform:translateX(-50%);white-space:nowrap}.navmore{font-size:23px;letter-spacing:1px;line-height:1}.editnav>span,.editnav>strong{font-size:16px;font-weight:400}.editnav>strong{font-weight:600}.content{flex:1;min-height:0;padding:0 16px;overflow:hidden}.content>h1{font-size:31px;font-weight:650;letter-spacing:-.8px;line-height:1.3;margin:10px 0 10px}.scope{display:flex;gap:8px;align-items:center;margin:0 0 13px;font-size:13px;color:#69696f}.scope img{width:24px;height:24px;border-radius:50%;background:#e6e4ef;object-fit:contain;padding:1px}.scope small{font-size:12px;color:#9a9aa0;margin-left:2px}.sectionlabel{font-size:12px;color:#85858c;text-transform:uppercase;margin:23px 16px 7px;letter-spacing:.1px}.group{background:var(--group);border-radius:11px;overflow:hidden;margin-bottom:0}.cell{height:49px;min-height:49px;display:flex;align-items:center;gap:10px;margin-left:16px;padding-right:16px;border-bottom:1px solid var(--separator);font-size:16px;font-weight:400;position:relative;line-height:1.3}.cell:last-child{border-bottom:0}.celltitle{white-space:nowrap}.value{margin-left:auto;white-space:nowrap;font-size:15px;color:#8b8b91}.pending .value{font-size:14px;color:#fff;background:var(--count);border-radius:12px;padding:1px 7px;min-width:21px;text-align:center}.chevron{font-size:25px;font-weight:300;color:#c3c3c9;line-height:1;margin-left:0;transform:translateY(-1px)}.rowicon{display:flex;align-items:center;justify-content:center;color:var(--accent);width:22px;flex-shrink:0}.rowicon svg{width:21px;height:21px}.switch{margin-left:auto;background:var(--toggle);border-radius:20px;width:43px;height:26px;padding:2px;box-shadow:inset 0 0 1px #0001}.switch:after{content:"";display:block;width:22px;height:22px;background:#fff;border-radius:50%;margin-left:17px;box-shadow:0 1px 3px #0002}.footnote{font-size:11px;line-height:1.7;color:#929298;margin:7px 16px 0}.footnote+.group{margin-top:24px}.accentrow{color:var(--accent)}.accentrow .chevron{margin-left:auto}.tick{margin-left:auto;color:var(--accent);font-size:20px}.delete{justify-content:center;margin-left:0;padding-right:0;color:#ff3b30;margin-top:0;font-size:15px}.home{height:5px;min-height:5px;width:116px;margin:17px auto 9px;background:#141416;border-radius:9px}.search{display:flex;align-items:center;gap:7px;background:var(--search);height:36px;border-radius:10px;padding:0 10px;color:#94949a;font-size:15px;margin:13px 0 24px}.search svg{width:16px;height:16px;flex-shrink:0}.month{display:flex;justify-content:space-between;align-items:center;font-size:13px;color:#84848b;margin:0 14px 9px}.month small{font-size:12px}.diaryentries{background:var(--group);border-radius:11px;overflow:hidden}.entry{padding:16px 15px 17px;border-bottom:1px solid var(--separator);margin-left:0}.entry:last-child{border:0}.entrytop{display:flex;align-items:center;gap:7px;font-size:14px}.entrytop>b{font-size:14px;font-weight:600}.entrytop>span{font-size:11px;color:#a0a0a6;margin-left:auto}.entrytop i{font-size:23px;font-style:normal;font-weight:300;color:#c3c3c9;line-height:1}.entry h3{font-size:15px;font-weight:400;margin-top:9px;color:#4b4b52}.entry p{font-size:12px;line-height:1.7;color:#99999f;margin-top:5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.diaryentries+.footnote{margin-top:13px}.lastupdate{display:flex;align-items:center;gap:6px;padding:22px 13px;font-size:10px;color:#9a9aa1}.lastupdate i{width:5px;height:5px;border-radius:50%;background:#9fbcb0}.lastupdate b{margin-left:auto;font-size:11px;color:var(--accent);font-weight:400}.bottomtools{display:flex;align-items:center;justify-content:space-between;height:43px;min-height:43px;padding:0 23px;color:var(--accent);border-top:1px solid var(--separator)}.bottomtools small{font-size:11px;color:#929298}.bottomtools svg{width:21px;height:21px}.textinput{padding:15px 16px;min-height:50px;font-size:16px}.texteditor{padding:15px 16px;min-height:140px;font-size:16px;line-height:1.9;color:#35353b}.editnav+.content .sectionlabel:first-child{margin-top:25px}.boardfoot{display:flex;justify-content:space-between;font-size:11px;color:#97949d;margin:16px 4px 0}
.native{--background:#f2f2f7;--group:#fff;--separator:#e7e7ec;--accent:#007aff;--search:#e5e5eb;--toggle:#34c759;--count:#ff3b30}
.reading{--background:#fffefb;--group:#fffefb;--separator:#eeece6;--accent:#ac820e;--search:#f1efe8;--toggle:#c39a34;--count:#b68e28}.reading .screen{border-color:#dedbd2}.reading .content{padding:0 22px}.reading .content>h1{font-size:30px;letter-spacing:-.4px}.reading .sectionlabel{margin:27px 0 8px;color:#a39881;font-size:11px;letter-spacing:1px}.reading .group{border-radius:0;border-top:1px solid #ebe6dc;border-bottom:1px solid #ebe6dc}.reading .cell{margin-left:0;padding-right:1px;height:52px}.reading .rowicon{width:19px}.reading .rowicon svg{width:19px;height:19px}.reading .celltitle{font-size:15px}.reading .footnote{margin-left:0;margin-right:0}.reading .scope img{display:none}.reading .scope{font-size:12px;margin-bottom:5px;color:#9f947d}.reading .scope small{border-left:1px solid #ded7c7;padding-left:8px}.reading .diaryentries{border-radius:0;background:transparent}.reading .entry{padding:19px 0 21px}.reading .entry h3{font-size:17px;font-weight:500;margin-top:12px;color:#37342d}.reading .entry p{font-size:13px;color:#aaa08c;margin-top:8px}.reading .entrytop>b{font-weight:400;color:#b49b65;font-size:12px}.reading .entrytop>span{font-size:10px;color:#b4ab98}.reading .entrytop i{display:none}.reading .month{margin-left:0;margin-right:0;color:#9b8b6a;font-size:12px}.reading .search{background:#f2f0e9;border-radius:8px}.reading .textinput,.reading .texteditor{padding-left:0;padding-right:0}.reading .texteditor{min-height:152px;font-size:17px}.reading .delete{color:#b67c6d}.reading .bottomtools{border-color:#eee8db}.reading .lastupdate{padding-left:0;padding-right:0}
.companion{--background:#fcfcfe;--group:#f5f4f8;--separator:#e9e7ef;--accent:#7861af;--search:#f0eef5;--toggle:#8570b7;--count:#8a76b4}.companion .content>h1{font-size:29px}.companion .group{border-radius:14px}.companion .sectionlabel{margin-left:2px;font-size:12px;color:#a298ad}.companion .footnote{margin-left:3px;margin-right:3px}.companion .scope{margin:13px 0 15px}.companion .scope img{width:29px;height:29px;background:#eeeaf5}.companion .scope small{margin-left:auto;font-size:10px;color:#a59bae}.companion .rowicon svg{width:19px;height:19px}.companion .rowicon{width:22px}.companion .cell{font-size:15px;height:50px}.companion .value{font-size:14px;color:#a299ad}.companion .cell.pending .value{color:#fff}.companion .diaryentries{border-radius:0;background:transparent}.companion .entry{padding:19px 2px 20px;border-bottom:1px solid #ece9f2}.companion .entrytop>b{font-weight:400;font-size:12px;color:#a193b2}.companion .entry h3{font-size:17px;font-weight:500;margin-top:10px;color:#41384c}.companion .entry p{font-size:12px}.companion .entry.first{border-left:2px solid #ab96ca;padding-left:13px}.companion .month{margin-left:2px}.companion .bottomtools{border:0}.companion .textinput,.companion .texteditor{background:#f7f6fa}.companion .tick{font-size:18px}.companion .delete{color:#ad7b90}
'''

variants=[('native','原生设置版','系统分组列表 · 蓝色操作 · 绿色开关'),('reading','阅读列表版','暖白底色 · 无卡片边框 · 文字优先'),('companion','轻量伴侣版','白色界面 · 少量淡紫 · 紧凑列表')]
for key,title,subtitle in variants:
    columns=''.join('<div><div class="pagelabel">'+labeltext+'</div>'+content+'</div>' for labeltext,content in [('主设置',overview()),('日记列表',diary()),('记忆编辑',editor())])
    body='<div class="heading"><div><b>'+title+'</b><span>'+subtitle+'</span></div><small>同样的功能，比较不同布局</small></div><div class="boards">'+columns+'</div><div class="boardfoot"><span>仅保留：每日日记／事实与约定／待确认记忆</span><span>静态设计原型 · 示例数据 · 非App运行截图</span></div>'
    (OUT/f'{key}.html').write_text('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=1263,initial-scale=1"><title>'+title+'</title><style>'+CSS+'</style></head><body class="'+key+'">'+body+'</body></html>',encoding='utf-8')
print(OUT)
