const PACKS = DATA.packs;

/* 体系维度：导入时按关键词自动归组（对应 DB 新增的 group 字段） */
const GROUPS = ['题材定位','结构节奏','人物与视角','文风语言','逻辑约束','禁忌清单','考据制度'];
function pickGroup(packCat, packName, name){
  // 只看规则名与包分类，不看正文，避免长文里到处命中关键词
  if (/禁忌/.test(name)) return '禁忌清单';
  if (packCat === '制度' || /官场|三省|六部|政事堂|票拟|批红|品级|铨选|卫所|州县|科举|法度/.test(name)) return '考据制度';
  if (/台词|文风|语言|描写|短句|用词|腔调/.test(name)) return '文风语言';
  if (/时间表|物证|线索|证据|常识|限制|监控|通讯|法医|账|链条|价格|损耗|流程|机制|边界|代价|对账|讯问|问话/.test(name)) return '逻辑约束';
  if (/结构|集数|单集|秒|章|节奏|卡点|开场|钩子|删集|反转|密度|收尾|开局|集末|整剧|场景|成本|规格|三定|爽点|打脸|反制|翻盘/.test(name)) return '结构节奏';
  if (/人物|角色|主角|反派|嫌疑|配角|关系|情感|视角|动机|人设|证人|侦探|女主|男主|村民|干部/.test(name)) return '人物与视角';
  return '题材定位';
}

let myRules = [];
let uid = 0;
function importPack(pack, idxs){
  idxs.forEach(i=>{
    const r = pack.rules[i];
    myRules.push({
      id:'r'+(uid++), name:r.name, content:r.content,
      packId:pack.id, packName:pack.name, packCat:pack.category,
      group:pickGroup(pack.category, pack.name, r.name),
      enabled:true
    });
  });
}

/* 初始：悬疑推理 12 + 短剧通则 10 + 都市逆袭 5 = 27，再手动补几条到 38 的规模感 */
const P = id => PACKS.find(p=>p.id===id);
importPack(P('suspense_mystery'), P('suspense_mystery').rules.map((_,i)=>i));
importPack(P('short_craft'), P('short_craft').rules.map((_,i)=>i));
importPack(P('short_urban_slap'), [0,1,2,5,6]);

const state = { group:'ALL', activeId: (myRules.find(r=>/法医/.test(r.name))||myRules[0]).id, q:'', libCat:'短剧', libPack:'short_craft', sel:{}, editing:false };

function visible(){
  let list = myRules;
  if (state.group !== 'ALL'){
    if (state.group.startsWith('PACK:')) list = list.filter(r=>r.packName===state.group.slice(5));
    else list = list.filter(r=>r.group===state.group);
  }
  if (state.q){
    const q = state.q.toLowerCase();
    list = list.filter(r=>(r.name+r.content).toLowerCase().includes(q));
  }
  return list;
}
function counts(){
  const m = {}; GROUPS.forEach(g=>m[g]=0);
  myRules.forEach(r=>{ m[r.group] = (m[r.group]||0)+1; });
  return m;
}
function renderTree(){
  const c = counts();
  let h = `<div class="cap"><span>规则体系</span><span title="demo 未实现">＋ 分组</span></div>
    <div class="gi all ${state.group==='ALL'?'on':''}" data-g="ALL"><span class="nm">全部规则</span><span class="n">${myRules.length}</span></div>`;
  GROUPS.forEach(g=>{
    h += `<div class="gi ${state.group===g?'on':''}" data-g="${g}"><span class="nm">${g}</span><span class="n">${c[g]||0}</span></div>`;
  });
  const byPack = {};
  myRules.forEach(r=>{ byPack[r.packName] = (byPack[r.packName]||0)+1; });
  h += `<div style="height:6px"></div><div class="cap" style="padding-top:10px"><span>来源</span></div>`;
  Object.keys(byPack).forEach(pn=>{
    h += `<div class="gi ${state.group==='PACK:'+pn?'on':''}" data-pack="${pn}"><span class="nm" style="font-weight:${state.group==='PACK:'+pn?600:400}">${pn}</span><span class="n">${byPack[pn]}</span></div>`;
  });
  const t = document.getElementById('tree');
  t.innerHTML = h;
  t.querySelectorAll('.gi').forEach(el=>{
    el.onclick = ()=>{
      state.group = el.dataset.pack ? 'PACK:'+el.dataset.pack : el.dataset.g;
      const v = visible();
      state.activeId = v.length ? v[0].id : null;
      state.editing = false;
      renderAll();
    };
  });
}
function renderList(){
  const list = visible();
  document.getElementById('listTitle').textContent =
    state.group==='ALL' ? '全部规则'
    : state.group.startsWith('PACK:') ? '来源 · '+state.group.slice(5) : state.group;
  document.getElementById('listMeta').textContent =
    `${list.length} 条 · 启用 ${list.filter(r=>r.enabled).length}`;
  document.getElementById('tabMineN').textContent = myRules.length;
  document.getElementById('headCnt').textContent =
    `${myRules.length} 条 · 全部启用 ${myRules.filter(r=>r.enabled).length}`;
  const rows = document.getElementById('rows');
  if (!list.length){ rows.innerHTML = '<div class="empty">这个分组下还没有规则</div>'; return; }
  rows.innerHTML = list.map(r=>{
    const first = r.content.split('。')[0] + '。';
    return `<div class="r ${r.id===state.activeId?'on':''} ${r.enabled?'':'off'}" data-id="${r.id}">
      <div class="body">
        <div class="nm"><span class="nt">${r.name}</span></div>
        <div class="sub">${first}</div>
        <div class="meta"><span class="chip pk">${r.packName}</span><span class="chip">${r.group}</span></div>
      </div>
      <div class="sw ${r.enabled?'on':''}" data-sw="${r.id}"></div>
    </div>`;
  }).join('');
  rows.querySelectorAll('.r').forEach(el=>{
    el.onclick = e=>{
      if (e.target.classList.contains('sw')) return;
      state.activeId = el.dataset.id; state.editing = false;
      renderList(); renderDetail();
    };
  });
  rows.querySelectorAll('.sw').forEach(el=>{
    el.onclick = e=>{
      e.stopPropagation();
      const r = myRules.find(x=>x.id===el.dataset.sw);
      r.enabled = !r.enabled;
      renderList(); renderDetail();
    };
  });
}
function clauses(content){
  return content.split(/[。；]/).map(s=>s.replace(/^[一二三四五六七八九十]+是/,'').trim()).filter(Boolean);
}
function numbers(content){
  const unit = '(?:秒|分钟|小时|天|个|条|人|字|集|章|元|万|%|次|场|倍|页|厘米|米)';
  const re = new RegExp('\\d+(?:\\.\\d+)?\\s?(?:～|~|-)\\s?\\d+(?:\\.\\d+)?\\s?' + unit + '?|\\d+(?:\\.\\d+)?\\s?' + unit, 'g');
  const m = content.match(re) || [];
  return Array.from(new Set(m.map(s=>s.replace(/\s+/g,' ').trim()))).slice(0,6);
}
function shortPhrase(s){
  const head = s.split('，')[0].replace(/^[一二三四五六七八九十0-9]+是?/,'').trim();
  return head.length > 20 ? head.slice(0,20) + '…' : head;
}
function checks(content){
  const raw = content.split(/[。；]/).map(s=>s.trim()).filter(Boolean)
    .filter(s=>/必须|禁止|不许|不能|每|至少|不超过|只在|只允许/.test(s))
    .map(shortPhrase).filter(Boolean);
  return Array.from(new Set(raw)).slice(0,4);
}
function renderDetail(){
  const box = document.getElementById('detail');
  const r = myRules.find(x=>x.id===state.activeId);
  if (!r){ box.innerHTML = '<div class="empty">左侧选一条规则</div>'; return; }

  const head = `<div class="dh">
    <div class="crumb">智能体规则 <span>›</span> <b>${r.group}</b></div>
    <h2>${r.name}</h2>
    <div class="tags">
      <span class="chip pk">${r.packName}</span>
      <span class="chip">${r.packCat}</span>
      <span class="chip">${r.enabled?'已启用':'已停用'}</span>
    </div>
  </div>`;

  if (state.editing){
    box.innerHTML = head + `<div class="db"><div class="sec">名称</div>
      <input id="edName" value="${r.name}" style="width:100%;border:1px solid #e4e4df;border-radius:9px;padding:8px 10px;font:inherit;outline:none">
      <div class="sec">条款正文</div>
      <textarea id="edBody" style="width:100%;height:360px;border:1px solid #e4e4df;border-radius:9px;padding:10px;font:inherit;line-height:1.7;resize:vertical;outline:none">${r.content}</textarea>
      <div style="margin-top:14px;display:flex;gap:8px"><button class="btn" id="saveRule">保存</button><button class="btn ghost" id="cancelEdit">取消</button></div>
      </div>`;
    box.querySelector('#cancelEdit').onclick = ()=>{ state.editing=false; renderDetail(); };
    box.querySelector('#saveRule').onclick = ()=>{
      r.name = box.querySelector('#edName').value.trim() || r.name;
      r.content = box.querySelector('#edBody').value.trim() || r.content;
      state.editing = false; renderList(); renderDetail(); toast('已保存 · 右栏编辑不用整页跳转');
    };
    return;
  }

  const cls = clauses(r.content);
  const cks = checks(r.content).filter(p=>!r.content.startsWith(p.replace('…','')));
  const nums = numbers(r.content);
  const sibs = myRules.filter(x=>x.group===r.group && x.id!==r.id).slice(0,3);
  const order = myRules.filter(x=>x.enabled).indexOf(r) + 1;

  box.innerHTML = head + `<div class="db">
    <div class="sec">条款</div>
    ${cls.map((s,i)=>`<div class="cl"><span class="no">${String(i+1).padStart(2,'0')}</span><span>${s}。</span></div>`).join('')}

    ${nums.length?`<div class="sec">硬约束 · 条款里的数字与阈值</div>
    <div style="display:flex;gap:6px;flex-wrap:wrap">${nums.map(n=>`<span class="chip" style="background:#fff">${n}</span>`).join('')}</div>`:''}

    <div class="sec">自检项（写章后可勾）</div>
    ${cks.length ? cks.map((s,i)=>`<div class="ck" data-ck="${i}"><div class="box"></div><span>${s}</span></div>`).join('')
      : `<div style="font-size:11.5px;color:#b0b6be;padding:2px 0">这条还没填自检项 · <span style="color:#4a4f57;cursor:pointer">＋ 添加检查点</span></div>`}

    <div class="sec">同组关联</div>
    ${sibs.map(s=>`<div class="rel" data-go="${s.id}"><i></i><span>${s.name}</span></div>`).join('') || '<div style="font-size:12px;color:#b0b6be">暂无</div>'}

    <div class="sec">送达位置</div>
    <div class="hit">
      <div class="hh"><span>拼进提示词时</span><span>顺序</span></div>
      <div class="hl">作用于全书 · 每次生成都送<span></span><em>第 ${order||1} 位</em></div>
      <div class="hl">本组共 ${myRules.filter(x=>x.group===r.group).length} 条 · 启用 ${myRules.filter(x=>x.group===r.group&&x.enabled).length}<span></span><em>${r.group}</em></div>
    </div>
  </div>
  <div class="df">
    <button class="btn" id="editBtn">编辑</button>
    <button class="btn ghost" id="tryBtn">试写对比</button>
    <button class="del" id="delBtn">${r.enabled?'停用':'启用'}</button>
  </div>`;

  box.querySelectorAll('.ck').forEach(el=>{
    el.onclick = ()=>el.classList.toggle('done');
  });
  box.querySelectorAll('.rel').forEach(el=>{
    el.onclick = ()=>{ state.activeId = el.dataset.go; renderList(); renderDetail(); };
  });
  box.querySelector('#editBtn').onclick = ()=>{ state.editing = true; renderDetail(); };
  box.querySelector('#tryBtn').onclick = ()=>toast('试写对比：同一段正文，带这条规则 / 不带，左右并排给两版');
  box.querySelector('#delBtn').onclick = ()=>{
    r.enabled = !r.enabled; renderList(); renderDetail();
  };
}

/* ---------- 规则库 ---------- */
function renderCatalog(){
  const cats = {};
  PACKS.forEach(p=>{ cats[p.category] = (cats[p.category]||0)+1; });
  const order = ['短剧','推理','古代','男频','女频','科幻','种田','系统流','都市','制度'];
  let h = `<div class="cap" style="padding:0 8px 8px"><span>分类</span></div>`;
  order.filter(c=>cats[c]).forEach(c=>{
    h += `<div class="gi ${state.libCat===c?'on':''}" data-cat="${c}"><span class="nm">${c}</span><span class="n">${cats[c]}</span></div>`;
  });
  const box = document.getElementById('libCat');
  box.innerHTML = h;
  box.querySelectorAll('.gi').forEach(el=>{
    el.onclick = ()=>{
      state.libCat = el.dataset.cat;
      const first = PACKS.find(p=>p.category===state.libCat);
      state.libPack = first ? first.id : null;
      renderCatalog(); renderPacks(); renderPackDetail();
    };
  });
}
function importedCount(pid){
  return myRules.filter(r=>r.packId===pid).length;
}
function renderPacks(){
  const list = PACKS.filter(p=>p.category===state.libCat);
  document.getElementById('libPacks').innerHTML = list.map(p=>{
    const n = importedCount(p.id);
    let badge = '';
    if (n >= p.rules.length) badge = `<span class="imp all">已全导入 ${n}/${p.rules.length}</span>`;
    else if (n > 0) badge = `<span class="imp">已导入 ${n}/${p.rules.length}</span>`;
    else badge = `<span class="imp">${p.rules.length} 条</span>`;
    return `<div class="pcard ${state.libPack===p.id?'on':''}" data-p="${p.id}">
      <div class="pn">${p.name}${badge}</div>
      <div class="ps">${p.summary}</div>
    </div>`;
  }).join('');
  document.getElementById('libPacks').querySelectorAll('.pcard').forEach(el=>{
    el.onclick = ()=>{ state.libPack = el.dataset.p; renderPacks(); renderPackDetail(); };
  });
}
function renderCart(){
  const packs = Object.keys(state.sel).filter(pid=>state.sel[pid] && state.sel[pid].size);
  const total = packs.reduce((a,pid)=>a+state.sel[pid].size,0);
  const cart = document.getElementById('cart');
  if (!total){
    cart.innerHTML = `<span>已选 0 条 · 可跨包勾选，一次导入</span><span class="sum">合计 0</span>`;
  } else {
    cart.innerHTML = `<span>已选</span>` +
      packs.map(pid=>{
        const p = PACKS.find(x=>x.id===pid);
        return `<span class="citem">${p.name} <b>${state.sel[pid].size}</b></span>`;
      }).join('') +
      `<span class="sum">合计 ${total} 条</span>`;
  }
}
function renderPackDetail(){
  const box = document.getElementById('libDetail');
  const p = PACKS.find(x=>x.id===state.libPack);
  if (!p){ box.innerHTML = '<div class="empty">左侧选一个分类</div>'; renderCart(); return; }
  if (!state.sel[p.id]) state.sel[p.id] = new Set();
  const sel = state.sel[p.id];
  const n = importedCount(p.id);
  const free = p.rules.map((r,i)=>i).filter(i=>!myRules.some(x=>x.packId===p.id && x.name===p.rules[i].name));

  box.innerHTML = `<div class="dh">
    <div class="crumb">规则库 <span>›</span> <b>${p.category}</b></div>
    <h2>${p.name}</h2>
    <div class="tags">
      <span class="chip">${p.rules.length} 条</span>
      <span class="chip pk">${n?`本作品已导入 ${n} 条`:'尚未导入'}</span>
    </div>
    <div style="margin-top:10px;font-size:12px;color:#8b9199;line-height:1.6">${p.summary}</div>
  </div>
  <div class="db" style="padding:10px 12px">
    <div style="display:flex;align-items:center;gap:8px;padding:0 4px 6px">
      <span class="sec" style="margin:0">包内规则</span>
      <span style="margin-left:auto;font-size:11px;color:#a2a8b0;cursor:pointer" id="selAll">${free.length?((free.every(i=>sel.has(i)))?'取消全选':'全选可导入 '+free.length+' 条'):'已全部在库'}</span>
    </div>
    ${p.rules.map((r,i)=>{
      const already = myRules.some(x=>x.packId===p.id && x.name===r.name);
      return `<div class="lr ${sel.has(i)?'sel':''} ${already?'locked':''}" data-i="${i}" data-locked="${already?1:0}">
        <div class="box"></div>
        <div class="lt"><b>${r.name}${already?' <span class="chip" style="margin-left:4px">已在库</span>':''}</b><p>${r.content}</p></div>
      </div>`;
    }).join('')}
  </div>
  <div class="df">
    <button class="btn" id="doImport">导入 ${sel.size} 条</button>
    <span style="font-size:11px;color:#a2a8b0">自动归入 ${GROUPS.length} 个维度</span>
    <button class="del" id="clearSel">清空已选</button>
  </div>`;

  box.querySelectorAll('.lr').forEach(el=>{
    el.onclick = ()=>{
      const i = +el.dataset.i;
      if (el.dataset.locked === '1'){ toast('「'+p.rules[i].name+'」已经在库里了，不会重复导入'); return; }
      if (sel.has(i)) sel.delete(i); else sel.add(i);
      renderPackDetail(); renderCart();
    };
  });
  box.querySelector('#selAll').onclick = ()=>{
    const allSel = free.length && free.every(i=>sel.has(i));
    if (allSel) state.sel[p.id] = new Set();
    else state.sel[p.id] = new Set(free);
    renderPackDetail(); renderCart();
  };
  box.querySelector('#clearSel').onclick = ()=>{
    state.sel = {}; renderPackDetail(); renderCart();
  };
  box.querySelector('#doImport').onclick = ()=>{
    if (!sel.size) { toast('先勾选要导入的规则'); return; }
    let total = 0;
    Object.keys(state.sel).forEach(pid=>{
      if (!state.sel[pid].size) return;
      const pk = PACKS.find(x=>x.id===pid);
      const skip = pk.rules.map((r,i)=>i).filter(i=>myRules.some(x=>x.packId===pid && x.name===pk.rules[i].name));
      const todo = [...state.sel[pid]].filter(i=>!skip.includes(i));
      if (todo.length){ importPack(pk, todo); total += todo.length; }
    });
    state.sel = {};
    state.group = 'ALL';
    const v = visible(); state.activeId = v.length ? v[0].id : null;
    switchTab('mine');
    renderAll();
    toast(`已导入 ${total} 条 · 按维度自动归组，规则数 ${myRules.length}`);
  };
  renderCart();
}

/* ---------- 通用 ---------- */
function toast(msg){
  const t = document.getElementById('toast');
  t.innerHTML = msg;
  t.classList.add('on');
  clearTimeout(t._tm);
  t._tm = setTimeout(()=>t.classList.remove('on'), 2600);
}
function switchTab(name){
  document.querySelectorAll('.tab').forEach(el=>el.classList.toggle('on', el.dataset.tab===name));
  document.getElementById('view-mine').classList.toggle('on', name==='mine');
  document.getElementById('view-lib').classList.toggle('on', name==='lib');
  if (name==='lib'){ renderCatalog(); renderPacks(); renderPackDetail(); }
}
function renderAll(){ renderTree(); renderList(); renderDetail(); }

document.querySelectorAll('.tab').forEach(el=>{
  el.onclick = ()=>switchTab(el.dataset.tab);
});
document.getElementById('q').oninput = e=>{
  state.q = e.target.value.trim();
  const v = visible();
  if (!v.some(r=>r.id===state.activeId)) state.activeId = v.length ? v[0].id : null;
  renderList(); renderDetail();
};
document.getElementById('groupSw').onclick = e=>{
  const list = visible();
  const allOn = list.every(r=>r.enabled);
  list.forEach(r=>r.enabled = !allOn);
  e.currentTarget.classList.toggle('on', !allOn);
  renderList(); renderDetail();
};

renderAll();
if (location.hash === '#lib') switchTab('lib'); else switchTab('mine');
