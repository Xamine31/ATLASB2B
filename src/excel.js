import ExcelJS from 'exceljs';
export const DEFAULT_ROOMS=[
 {name:'SGL',label:'Chambre individuelle',capacity:1},
 {name:'DBL',label:'Chambre double',capacity:2},
 {name:'TRIPL',label:'Chambre triple',capacity:3},
 {name:'QDL',label:'Chambre quadruple',capacity:4},
 {name:'SUITE',label:'Suite',capacity:2},
 {name:'JUNIOR SUITE',label:'Suite junior',capacity:2},
 {name:'SGL SV',label:'Individuelle vue mer',capacity:1},
 {name:'DBL SV',label:'Double vue mer',capacity:2},
 {name:'TRPL SV',label:'Triple vue mer',capacity:3},
 {name:'QDL SV',label:'Quadruple vue mer',capacity:4},
];
export const DEFAULT_PROMOS=[
 {code:'CHILD_0_2',label:'Enfant 0–2 ans',kind:'child',row:16},
 {code:'CHILD_2_6',label:'Enfant 2–6 ans',kind:'child',row:17},
 {code:'CHILD_6_11',label:'Enfant 6–11 ans',kind:'child',row:18},
 {code:'THIRD_ADULT',label:'3e adulte',kind:'special',row:20},
 {code:'EARLY_BOOKING',label:'Réservation anticipée',kind:'special',row:21},
 {code:'HONEYMOON',label:'Voyage de noces',kind:'special',row:22},
 {code:'SENIOR',label:'Senior',kind:'special',row:23},
];
const BOARDS=['RO','BB','HB','FB','ALL IN'];
const cellText=c=>{const v=c.value;return v==null?'':typeof v==='object'?(v.result??v.text??v.richText?.map(x=>x.text).join('')??'').toString().trim():String(v).trim()};
const dateISO=(y,m,d)=>{const val=new Date(Date.UTC(y,m-1,d));if(val.getUTCMonth()!==m-1||val.getUTCDate()!==d)throw Error('Date invalide dans la grille');return val.toISOString().slice(0,10)};
function dateRange(label,year){const m=label.match(/(\d{1,2})\s*\/\s*(\d{1,2})\s*[-–]\s*(\d{1,2})\s*\/\s*(\d{1,2})/);if(!m)throw Error('Période non reconnue : '+label);const [d1,mo1,d2,mo2]=m.slice(1).map(Number);let y1=year+(mo1<11?1:0),y2=year+(mo2<11?1:0);if(y2<y1||(y2===y1&&(mo2<mo1||(mo2===mo1&&d2<d1))))y2=y1+1;return [dateISO(y1,mo1,d1),dateISO(y2,mo2,d2)]}
function percent(s){if(!s)return null;const normalized=String(s).trim().replace(/\s/g,'').replace(',','.');if(!normalized.endsWith('%'))throw Error(`Réduction invalide « ${s} » : utiliser -10%`);const n=Number(normalized.slice(0,-1));if(!Number.isFinite(n)||n>0||n< -100)throw Error('La réduction doit être entre -100% et 0%');return Math.abs(n)}
export async function parseNatbeds(file,year){
 if(!Number.isInteger(Number(year))||year<2020||year>2100)throw Error('Année de saison invalide');
 const wb=new ExcelJS.Workbook();await wb.xlsx.load(await file.arrayBuffer());const ws=wb.worksheets[0];
 if(!ws||cellText(ws.getCell(3,1)).toUpperCase()!=='ROOM TYPE')throw Error('Modèle NATBEDS non reconnu : A3 doit contenir ROOM TYPE');
 const periods=[];for(let p=0;p<6;p++){const c=2+p*5;const dates=dateRange(cellText(ws.getCell(3,c)),Number(year));for(let j=0;j<5;j++)if(cellText(ws.getCell(4,c+j)).toUpperCase()!==BOARDS[j])throw Error('En-têtes de pension incorrects colonne '+(c+j));periods.push({c,dates})}
 const rates=[];for(let r=5;r<=14;r++){const room=cellText(ws.getCell(r,1)).toUpperCase().replace(/\s+/g,' ').trim();if(!room)continue;for(const p of periods)for(let j=0;j<5;j++){const s=cellText(ws.getCell(r,p.c+j));if(!s)continue;const n=Number(s.replace(/\s/g,'').replace(',','.'));if(!Number.isFinite(n)||n<0||n>100000)throw Error(`Tarif incorrect ligne ${r}, colonne ${p.c+j}`);rates.push({room_name:room,board:BOARDS[j],date_start:p.dates[0],date_end:p.dates[1],net_price:n})}}
 if(!rates.length)throw Error('Aucun prix trouvé. Le modèle Excel est-il rempli ?');
 const promotions=DEFAULT_PROMOS.map(p=>{const values=periods.map(period=>percent(cellText(ws.getCell(p.row,period.c))));const nonEmpty=values.filter(x=>x!==null);return {code:p.code,label:p.label,kind:p.kind,discount_percent:nonEmpty.length?nonEmpty[0]:0,periods:periods.filter((_,i)=>values[i]!==null).map((x)=>({date_start:x.dates[0],date_end:x.dates[1],discount_percent:values[periods.indexOf(x)]})),has_value:nonEmpty.length>0,variation:nonEmpty.some(x=>x!==nonEmpty[0])}});
 return {rates,promotions,periods:periods.map(p=>({date_start:p.dates[0],date_end:p.dates[1]})),rooms:[...new Set(rates.map(x=>x.room_name))]};
}
export async function exportRates(hotel,rows){const wb=new ExcelJS.Workbook(),ws=wb.addWorksheet('Tarifs');ws.addRow(['Hôtel','Chambre','Pension','Début','Fin','Tarif net EUR']);for(const r of rows)ws.addRow([hotel,r.room_name,r.board,r.date_start,r.date_end,Number(r.net_price)]);ws.columns=[{width:28},{width:23},{width:14},{width:17},{width:17},{width:18}];ws.getRow(1).font={bold:true,color:{argb:'FFFFFFFF'}};ws.getRow(1).fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF252A24'}};const buff=await wb.xlsx.writeBuffer();const url=URL.createObjectURL(new Blob([buff],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}));const a=document.createElement('a');a.href=url;a.download=`tarifs_${hotel.replace(/[^a-z0-9]/gi,'_')}.xlsx`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1500)}
