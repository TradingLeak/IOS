'use strict';
const paths={
  navigation:'<path d="m20 4-6 16-3-7-7-3Z"/>',
  map:'<path d="m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3Z"/><path d="M9 3v15M15 6v15"/>',
  gauge:'<path d="M5 18a9 9 0 1 1 14 0Z"/><path d="m12 13 4-5M6 12H5m7-6V5m6 7h1"/><circle cx="12" cy="14" r="1"/>',
  download:'<path d="M12 3v12m-4-4 4 4 4-4M4 15v5h16v-5"/>',
  settings:'<path d="m9 3-1 3-3 1-2 4 2 2v4l4 3 3-1 3 1 4-3v-4l2-2-2-4-3-1-1-3Z"/><circle cx="12" cy="12" r="3"/>',
  layers:'<path d="m12 3 10 5-10 5L2 8Zm-9 9 9 5 9-5M3 16l9 5 9-5"/>',
  search:'<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  mic:'<rect x="9" y="2" width="6" height="13" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3m-3 0h6"/>',
  camera:'<rect x="3" y="6" width="13" height="13" rx="3"/><path d="m16 10 5-3v11l-5-3"/><circle cx="9" cy="12" r="2.5"/>',
  flag:'<path d="M5 21V3m0 1c5-4 9 4 15 0v10c-6 4-10-4-15 0"/>',
  locate:'<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3"/>',
  plus:'<path d="M12 5v14M5 12h14"/>',
  'arrow-right':'<path d="M4 12h16m-6-6 6 6-6 6"/>',
  'arrow-up':'<path d="M12 21V3m-6 6 6-6 6 6"/>',
  'chevron-right':'<path d="m9 5 7 7-7 7"/>',
  'chevron-down':'<path d="m6 9 6 6 6-6"/>',
  'turn-right':'<path d="M6 21V11a3 3 0 0 1 3-3h11m-5-5 5 5-5 5"/>',
  more:'<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
  x:'<path d="m6 6 12 12M6 18 18 6"/>',
  check:'<path d="m5 12 4 4L19 6"/>',
  'check-circle':'<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
  circle:'<circle cx="12" cy="12" r="9"/>',
  info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v.2"/>',
  shield:'<path d="M12 2 3 6v6c0 5 9 10 9 10s9-5 9-10V6Z"/><path d="m8 12 3 3 5-6"/>',
  wifi:'<path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0m-11 4a6 6 0 0 1 8 0M12 20h.01"/>',
  'wifi-off':'<path d="m3 3 18 18M2 8a16 16 0 0 1 4-2m5-1a16 16 0 0 1 11 3M5 12a11 11 0 0 1 5-2m6 1 3 1m-11 4a6 6 0 0 1 8 0M12 20h.01"/>',
  volume:'<path d="m11 4-6 5H2v6h3l6 5ZM16 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
  mirror:'<path d="M12 2v2m0 4v2m0 4v2m0 4v2M8 6l-6 6 6 6Zm8 0 6 6-6 6Z"/>',
  database:'<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v14c0 4 16 4 16 0V5M4 12c0 4 16 4 16 0"/>',
  sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1 1m12 12 1 1M5 19l1-1M18 6l1-1"/>',
  signal:'<path d="M4 19v-3m5 3v-7m5 7V8m5 11V4"/>',
  mouse:'<rect x="6" y="2" width="12" height="20" rx="6"/><path d="M12 3v5"/>'
};
function icon(name){return `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name]||paths.info}</svg>`;}
function icons(root=document){root.querySelectorAll('[data-icon]').forEach(el=>el.innerHTML=icon(el.dataset.icon));}
const $=s=>document.querySelector(s);
const storage={get(){try{return JSON.parse(localStorage.getItem('vietmap.html-demo.v1')||'{}')||{};}catch{return{};}},set(value){try{localStorage.setItem('vietmap.html-demo.v1',JSON.stringify(value));}catch{/* Demo works without persistence. */}}};
const saved=storage.get();
const state={page:'map',provider:saved.provider==='osm'?'osm':'apple',downloaded:saved.downloaded===true,wifiOnly:saved.wifiOnly!==false,voice:saved.voice!==false,mirror:saved.mirror===true,awake:saved.awake!==false,speed:48,gps:true,downloading:false,progress:0,verifying:false,navigating:false,distance:350,zoom:1,destination:'Hồ Hoàn Kiếm'};
let downloadTimer=null,verifyTimer=null,driveTimer=null,toastTimer=null,currentSheet=null,lastFocus=null;
const modal=$('#modalBackdrop');
function persist(){storage.set({provider:state.provider,downloaded:state.downloaded,wifiOnly:state.wifiOnly,voice:state.voice,mirror:state.mirror,awake:state.awake});}
function toast(text){$('#toast').textContent=text;$('#toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('#toast').classList.remove('visible'),2900);}
function setPage(page){if(!['map','hud','data','settings'].includes(page))return;state.page=page;document.querySelectorAll('.page').forEach(el=>el.classList.toggle('active',el.id===`page-${page}`));document.querySelectorAll('.tab-bar [data-page],.step[data-page]').forEach(el=>{el.classList.toggle('active',el.dataset.page===page);if(el.closest('.tab-bar'))el.setAttribute('aria-current',el.dataset.page===page?'page':'false');});$('.phone').classList.toggle('hud-mode',page==='hud');render();}
function render(){
  const osm=state.provider==='osm',locked=osm&&!state.downloaded;
  $('#providerName').textContent=osm?'OSM Việt Nam':'Apple Maps';$('#settingsProvider').textContent=osm?'OpenStreetMap':'Apple Maps';
  $('#offlineChip').textContent=state.downloading?'Đang tải mô phỏng…':state.downloaded?'Đã tải Việt Nam':'Việt Nam offline';
  $('#mapCanvas').classList.toggle('osm',osm);$('#mapCanvas').classList.toggle('locked',locked);$('#missingMap').hidden=!locked;
  $('#mapCanvas').setAttribute('aria-hidden',String(locked));$('#cameraBanner').hidden=locked||!state.gps;
  $('#miniSpeed').textContent=state.gps?state.speed:'—';$('#hudSpeed').textContent=state.gps?state.speed:'—';$('#sliderValue').textContent=`${state.speed} km/h`;
  $('#speedSlider').value=state.speed;const speeding=state.gps&&state.speed>62;$('.hud-dial').classList.toggle('speeding',speeding);
  $('#speedState').innerHTML=`<span></span>${!state.gps?'CHƯA CÓ TÍN HIỆU GPS':speeding?'VƯỢT GIỚI HẠN · HÃY GIẢM TỐC':'TRONG GIỚI HẠN AN TOÀN'}`;
  $('#gpsBadge').innerHTML=`<span class="live-dot"></span>${state.gps?'GPS tốt':'Mất GPS'}`;$('#gpsBadge').classList.toggle('lost',!state.gps);$('#hudAlert').hidden=!state.gps;
  $('#hudDistance').textContent=state.distance;$('#cameraDistance').innerHTML=`${state.distance} <small>m</small>`;
  $('#hudMirrorable').classList.toggle('mirrored',state.mirror);$('#mirrorButton').classList.toggle('selected',state.mirror);$('#mirrorButton').setAttribute('aria-pressed',String(state.mirror));$('#voiceButton').classList.toggle('selected',state.voice);$('#voiceButton').setAttribute('aria-pressed',String(state.voice));
  $('#mirrorSetting').checked=state.mirror;$('#voiceSetting').checked=state.voice;$('#wifiSetting').checked=state.wifiOnly;$('#awakeSetting').checked=state.awake;
  $('#navigateLabel').textContent=state.navigating?'Kết thúc':'Bắt đầu';$('#routeLine').classList.toggle('navigating',state.navigating);$('#routeCard .route-title h3').textContent=state.destination;
  $('#downloadDot').hidden=!state.downloading;
  if(state.downloaded){$('#dataState').innerHTML=`<div class="downloaded-state">${icon('check-circle')} Đã lưu trạng thái demo trên trình duyệt</div><button class="secondary-button" data-action="use-osm">Mở bản đồ OSM Việt Nam ${icon('arrow-right')}</button><button class="secondary-button" data-action="remove-map">Xoá dữ liệu mô phỏng</button>`;}
  else if(state.downloading){$('#dataState').innerHTML=`<div class="progress-title"><span>${state.verifying?'Đang mô phỏng kiểm tra…':'Đang mô phỏng tải gói Việt Nam'}</span><strong>${Math.floor(state.progress)}%</strong></div><div class="progress-track"><div class="progress-fill" style="width:${state.progress}%"></div></div><button class="secondary-button" data-action="download">Xem tiến trình ${icon('arrow-right')}</button>`;}
  else{$('#dataState').innerHTML=`<button class="primary-button" data-action="download">${icon('download')} Tải bản đồ Việt Nam</button><button class="secondary-button" data-action="download">Chưa tải · Chỉ mô phỏng, không tốn dung lượng</button>`;}
}
function showSheet(type,html){if(modal.hidden)lastFocus=document.activeElement;currentSheet=type;$('#sheetContent').innerHTML=html;icons($('#sheetContent'));modal.hidden=false;document.querySelectorAll('.page,.tab-bar').forEach(el=>el.inert=true);$('#sheet').focus();$('#sheet').scrollTop=0;}
function closeSheet(){modal.hidden=true;currentSheet=null;document.querySelectorAll('.page,.tab-bar').forEach(el=>el.inert=false);if(lastFocus&&lastFocus.isConnected)lastFocus.focus();else document.querySelector(`.tab-bar [data-page="${state.page}"]`).focus();}
function providers(){showSheet('providers',`<div class="sheet-icon">${icon('layers')}</div><span class="demo-badge">BẢN XEM TRƯỚC</span><h2 id="sheetTitle">Bản đồ theo cách bạn chọn.</h2><p class="sheet-description">Hai nguồn bản đồ, một trải nghiệm liền mạch.<br>Ghim, lộ trình và HUD vẫn luôn ở đó.</p><button class="provider-option ${state.provider==='apple'?'selected':''}" data-action="choose-apple"><span class="setting-icon blue">${icon('map')}</span><span><strong>Apple Maps</strong><small>Bản đồ Apple · Giao thông · Vệ tinh</small></span><span>${icon(state.provider==='apple'?'check-circle':'circle')}</span></button><button class="provider-option ${state.provider==='osm'?'selected':''}" data-action="choose-osm"><span class="setting-icon green">${icon('database')}</span><span><strong>OpenStreetMap</strong><small>Gói Việt Nam · ${state.downloaded?'Đã lưu trạng thái demo':'Cần tải về máy'}</small></span><span>${icon(state.provider==='osm'?'check-circle':'circle')}</span></button><p class="provider-note">Sơ đồ trong demo được vẽ minh hoạ, không lấy dữ liệu Apple hoặc OSM thật. Trong app iOS, tìm kiếm và tính tuyến vẫn sử dụng dịch vụ Apple Maps.</p>`);}
function downloadSheet(){
  if(state.downloaded){showSheet('download-success',`<div class="success-copy"><div class="success-icon">${icon('check')}</div><span class="demo-badge">HOÀN TẤT MÔ PHỎNG</span><h2 id="sheetTitle">Việt Nam đã sẵn sàng.</h2><p>Trạng thái “đã tải” được lưu trong trình duyệt.<br>Không có dữ liệu bản đồ thật được tải xuống.</p></div><div class="package-row"><span class="package-flag">VN</span><span><strong>Việt Nam</strong><small>OpenStreetMap · Gói minh hoạ</small></span><span>1,26 GB</span></div><button class="primary-button" data-action="use-osm">Khám phá bản đồ ${icon('arrow-right')}</button><button class="cancel-download" data-action="remove-map">Xoá trạng thái đã tải</button>`);return;}
  showSheet('download',`<div class="sheet-icon">${icon('download')}</div><span class="demo-badge">TẢI DỮ LIỆU MÔ PHỎNG</span><h2 id="sheetTitle">Mang Việt Nam<br>theo mọi hành trình.</h2><p class="sheet-description">Tải một lần, xem bản đồ ngay cả khi không có mạng. Gói dữ liệu chỉ dành cho khu vực Việt Nam.</p><div class="package-row"><span class="package-flag">VN</span><span><strong>Việt Nam</strong><small>OpenStreetMap · Phiên bản 2026.10</small></span><span>1,26 GB</span></div><div class="download-info">${icon('shield')} Mô phỏng xác minh gói dữ liệu trước khi cài</div><div class="download-info">${icon('map')} Chỉ khu vực Việt Nam · Dung lượng minh hoạ</div><label class="download-wifi"><span>${icon('wifi')} Chỉ tải qua Wi-Fi</span><input id="downloadWifi" class="switch" type="checkbox" ${state.wifiOnly?'checked':''} ${state.downloading?'disabled':''}></label><div id="downloadControls"></div><p class="sheet-footnote">Demo không tải file, không đo Wi-Fi và không chiếm 1,26 GB.<br>App iOS thật cần gói MBTiles Việt Nam và máy chủ phân phối.</p>`);updateDownloadControls();}
function updateDownloadControls(){
  if(currentSheet!=='download')return;const target=$('#downloadControls');if(!target)return;
  if(state.downloading){
    if(!target.querySelector('#downloadPercent'))target.innerHTML=`<div class="progress-wrap"><div class="progress-title"><span id="downloadStage"></span><strong id="downloadPercent"></strong></div><div class="progress-track"><div id="downloadProgressFill" class="progress-fill"></div></div><button class="cancel-download" data-action="cancel-download">Huỷ tải mô phỏng</button></div>`;
    $('#downloadStage').textContent=state.verifying?'Mô phỏng xác minh SHA-256…':'Đang mô phỏng tải dữ liệu…';
    $('#downloadPercent').textContent=`${Math.floor(state.progress)}%`;
    $('#downloadProgressFill').style.width=`${state.progress}%`;
  }else{target.innerHTML=`<button class="primary-button" data-action="start-download">${icon('download')} Tải bản đồ · 1,26 GB</button>`;}
  const wifi=$('#downloadWifi');if(wifi)wifi.disabled=state.downloading;
}
function startDownload(){if(state.downloading)return;state.downloading=true;state.progress=0;state.verifying=false;render();updateDownloadControls();downloadTimer=setInterval(()=>{state.progress=Math.min(95,state.progress+5);if(state.progress===95){clearInterval(downloadTimer);downloadTimer=null;state.verifying=true;verifyTimer=setTimeout(()=>{state.progress=100;state.verifying=false;state.downloading=false;state.downloaded=true;persist();render();if(currentSheet==='download')downloadSheet();toast('Hoàn tất mô phỏng · Không có file được tải');verifyTimer=null;},900);}render();updateDownloadControls();},230);}
function cancelDownload(){clearInterval(downloadTimer);clearTimeout(verifyTimer);downloadTimer=null;verifyTimer=null;state.downloading=false;state.progress=0;state.verifying=false;render();updateDownloadControls();toast('Đã huỷ tải mô phỏng');}
function selectProvider(provider){state.provider=provider;persist();render();closeSheet();if(provider==='osm'&&!state.downloaded)downloadSheet();else toast(provider==='osm'?'Đã chọn OSM · Sơ đồ minh hoạ':'Đã chọn Apple Maps · Sơ đồ minh hoạ');}
function useOSM(){if(!state.downloaded){downloadSheet();return;}state.provider='osm';persist();closeSheet();setPage('map');toast('Bản đồ OSM Việt Nam · Chế độ minh hoạ');}
function removeMap(){if(state.downloading)cancelDownload();state.downloaded=false;state.progress=0;persist();render();if(currentSheet)downloadSheet();toast('Đã xoá trạng thái bản đồ mô phỏng');}
function navigate(){if(state.provider==='osm'&&!state.downloaded){downloadSheet();return;}state.navigating=!state.navigating;if(state.navigating){state.distance=350;toast('Bắt đầu mô phỏng hành trình · Không dùng để lái xe');driveTimer=setInterval(()=>{if(state.gps){state.distance-=Math.max(8,Math.round(state.speed/3.6));if(state.distance<30){state.distance=500;toast('Đã qua camera mô phỏng · Tiếp tục hành trình');}render();}},1000);}else{clearInterval(driveTimer);driveTimer=null;state.distance=350;toast('Đã kết thúc hành trình mô phỏng');}render();}
function routeDetails(){showSheet('route',`<div class="sheet-icon">${icon('navigation')}</div><span class="demo-badge">LỘ TRÌNH MÔ PHỎNG</span><h2 id="sheetTitle">Đến ${state.destination}</h2><p class="sheet-description">18 phút · 6,4 km · Chỉ dẫn bên dưới là minh hoạ,<br>không phản ánh lộ trình thực tế.</p><div class="route-step"><span>${icon('arrow-up')}</span><div><strong>Đi thẳng trên Phan Đình Phùng</strong><small>Tiếp tục khoảng 800 m</small></div></div><div class="route-step"><span>${icon('turn-right')}</span><div><strong>Rẽ phải ở ngã tư phía trước</strong><small>Tiếp tục khoảng 1,2 km</small></div></div><div class="route-step"><span>${icon('camera')}</span><div><strong>Chú ý camera giao thông</strong><small>Tuân thủ biển báo thực tế</small></div></div><div class="route-step"><span>${icon('flag')}</span><div><strong>Đến ${state.destination}</strong><small>Kết thúc hành trình minh hoạ</small></div></div><button class="primary-button" data-action="start-from-route">${state.navigating?'Kết thúc mô phỏng':'Bắt đầu mô phỏng'} ${icon('navigation')}</button>`);}
const places=[{name:'Hồ Hoàn Kiếm',description:'Hoàn Kiếm, Hà Nội',type:'flag'},{name:'Hồ Tây',description:'Tây Hồ, Hà Nội',type:'map'},{name:'Lăng Chủ tịch Hồ Chí Minh',description:'Ba Đình, Hà Nội',type:'flag'},{name:'Văn Miếu Quốc Tử Giám',description:'Đống Đa, Hà Nội',type:'flag'}];
function normalized(s){return s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/đ/g,'d').replace(/Đ/g,'D').toLowerCase();}
function search(){showSheet('search',`<span class="demo-badge">TÌM KIẾM MINH HOẠ</span><h2 id="sheetTitle">Chuyến đi tiếp theo?</h2><div class="sheet-search">${icon('search')}<input id="placeSearch" type="search" placeholder="Tìm trong địa điểm mẫu…" aria-label="Tìm địa điểm mẫu" autocomplete="off"></div><div id="searchResults" class="search-results"></div><p class="provider-note">4 địa điểm mẫu có sẵn trong demo. Không gửi truy vấn tới dịch vụ bản đồ.</p>`);searchResults('');$('#placeSearch').focus();}
function searchResults(query){const found=places.filter(p=>normalized(p.name).includes(normalized(query)));$('#searchResults').innerHTML=found.length?found.map(p=>`<button class="search-result" data-action="select-place" data-place="${places.indexOf(p)}"><span>${icon(p.type)}</span><span><strong>${p.name}</strong><small>${p.description}</small></span></button>`).join(''):'<p class="search-empty">Chưa có địa điểm này trong dữ liệu mẫu.<br>Thử “Hồ Tây” hoặc “Hồ Hoàn Kiếm”.</p>';}
function reset(){clearInterval(downloadTimer);clearTimeout(verifyTimer);clearInterval(driveTimer);Object.assign(state,{provider:'apple',downloaded:false,wifiOnly:true,voice:true,mirror:false,awake:true,speed:48,gps:true,downloading:false,progress:0,verifying:false,navigating:false,distance:350,zoom:1,destination:'Hồ Hoàn Kiếm'});persist();closeSheet();$('#mapDrawing').removeAttribute('transform');setPage('map');toast('Đã đặt lại bản demo về trạng thái ban đầu');}
const actions={providers,download:downloadSheet,'choose-apple':()=>selectProvider('apple'),'choose-osm':()=>selectProvider('osm'),'start-download':startDownload,'cancel-download':cancelDownload,'use-osm':useOSM,'remove-map':removeMap,navigate,'route-details':routeDetails,'start-from-route':()=>{closeSheet();navigate();},search,mirror:()=>{state.mirror=!state.mirror;persist();render();toast(state.mirror?'Đã phản chiếu nội dung HUD':'Đã tắt phản chiếu');},voice:()=>{state.voice=!state.voice;persist();render();toast(state.voice?'Giọng nói: bật (mô phỏng, không phát âm thanh)':'Giọng nói: tắt');},gps:()=>{state.gps=!state.gps;render();toast(state.gps?'GPS mô phỏng đã được khôi phục':'Mô phỏng mất GPS · Đã ẩn dữ liệu tốc độ');},recenter:()=>{state.zoom=1;$('#mapDrawing').removeAttribute('transform');toast('Về vị trí minh hoạ của bạn');},zoom:()=>{state.zoom=state.zoom===1?1.3:1;$('#mapDrawing').setAttribute('transform',`translate(215 425) scale(${state.zoom}) translate(-215 -425)`);},'select-place':(button)=>{const place=places[Number(button.dataset.place)];if(!place)return;state.destination=place.name;closeSheet();setPage('map');toast('Đã chọn điểm đến · Tuyến trên sơ đồ vẫn là minh hoạ');},reset};
document.addEventListener('click',event=>{const button=event.target.closest('button');if(!button||button.disabled)return;if(button.dataset.page){if(!modal.hidden)closeSheet();setPage(button.dataset.page);return;}if(button.dataset.action&&actions[button.dataset.action])actions[button.dataset.action](button);});
$('#closeSheet').addEventListener('click',closeSheet);modal.addEventListener('click',event=>{if(event.target===modal)closeSheet();});
document.addEventListener('keydown',event=>{if(modal.hidden)return;if(event.key==='Escape'){closeSheet();return;}if(event.key==='Tab'){const items=[...$('#sheet').querySelectorAll('button:not(:disabled),a[href],input:not(:disabled),[tabindex="0"]')];const first=items[0],last=items[items.length-1];if(!first){event.preventDefault();return;}if(event.shiftKey&&(document.activeElement===first||document.activeElement===$('#sheet'))){last.focus();event.preventDefault();}else if(!event.shiftKey&&(document.activeElement===last||document.activeElement===$('#sheet'))){first.focus();event.preventDefault();}}});
document.addEventListener('input',event=>{if(event.target.id==='speedSlider'){state.speed=Number(event.target.value);render();}if(event.target.id==='placeSearch')searchResults(event.target.value);});
document.addEventListener('change',event=>{const el=event.target;switch(el.id){case'wifiSetting':case'downloadWifi':state.wifiOnly=el.checked;break;case'voiceSetting':state.voice=el.checked;toast(state.voice?'Giọng nói: bật (mô phỏng)':'Giọng nói: tắt');break;case'mirrorSetting':state.mirror=el.checked;break;case'awakeSetting':state.awake=el.checked;toast('Giữ sáng: mô phỏng tuỳ chọn, không điều khiển màn hình');break;default:return;}persist();render();});
$('.brand').addEventListener('click',event=>{event.preventDefault();setPage('map');});
icons();setPage('map');
// Preview has no network calls, location access, real speech or multi-gigabyte downloads.
