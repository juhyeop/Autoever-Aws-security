export const DEMO_NOW = Date.parse('2026-09-18T15:00:00+09:00');
export const regions = [
  {id:'ap-northeast-2',name:'서울',en:'SEOUL',lon:126.978,lat:37.566,resource:'i-seoul-app-01'},
  {id:'ap-northeast-1',name:'도쿄',en:'TOKYO',lon:139.69,lat:35.68,resource:'i-tokyo-app-01'},
  {id:'ap-southeast-1',name:'싱가포르',en:'SINGAPORE',lon:103.82,lat:1.35,resource:'i-singapore-app-01'},
  {id:'eu-central-1',name:'프랑크푸르트',en:'FRANKFURT',lon:8.68,lat:50.11,resource:'i-frankfurt-app-01'},
  {id:'us-east-1',name:'버지니아',en:'VIRGINIA',lon:-77.49,lat:38.75,resource:'i-virginia-app-01'},
  {id:'global',name:'글로벌 / 위치 미상',en:'GLOBAL',resource:null},
];
export const severityColors = {Critical:'#EF777F',High:'#E7A064',Medium:'#D8CA78',Low:'#32D4BE'};
export const sources = ['GuardDuty','Security Hub','Config','Inspector','Trivy','CloudWatch'];
export const statuses = ['신규','승인 대기','조치 실행 중','재검증 대기','재검증 중','해결','재검증 실패'];
const scenarios = [
  {scenario:'SEC-01',title:'SSH 포트 외부 공개',source:'Config',severity:'High',criterion:'0.0.0.0/0에 대한 TCP 22 인바운드 규칙 수',before:1,after:0,unit:'개',evidence:'sg-web-01의 TCP 22 인바운드가 0.0.0.0/0에 공개되어 있습니다.',recommendation:'해당 공개 규칙을 회수하고 SSM 연결 상태를 확인합니다.',mode:'자동'},
  {scenario:'SEC-02',title:'HTTP 보안 헤더 누락',source:'Security Hub',severity:'Medium',criterion:'필수 보안 헤더 누락 수 (동일 URL / 동일 헤더 집합)',before:3,after:0,unit:'개',evidence:'GET / 응답에 X-Content-Type-Options 등 필수 헤더 3개가 없습니다. 데모 검사 결과를 정규화한 항목입니다.',recommendation:'Nginx 응답 헤더 설정을 적용한 뒤 같은 URL을 재검사합니다.',mode:'자동'},
  {scenario:'SEC-03',title:'MySQL 3306 포트 과다 공개',source:'Config',severity:'Critical',criterion:'0.0.0.0/0에 대한 TCP 3306 인바운드 규칙 수',before:1,after:0,unit:'개',evidence:'sg-db-manual의 TCP 3306 인바운드가 외부 전체 주소를 허용합니다.',recommendation:'DB 인바운드를 애플리케이션 보안 그룹으로 제한합니다.',mode:'수동'},
  {scenario:'SEC-04',title:'컨테이너 이미지 취약점',source:'Trivy',severity:'High',criterion:'고정 검사 DB demo-20260918의 HIGH 이상 취약점 수',before:12,after:2,unit:'개',evidence:'app:1.2 이미지에서 HIGH 이상 취약점 12개가 발견되었습니다. 동일 검사 DB로 비교합니다.',recommendation:'수정된 app:1.3 이미지로 교체하고 동일 기준으로 재검사합니다.',mode:'수동'},
  {scenario:'DETECT-01',title:'비정상 외부 통신 탐지',source:'GuardDuty',severity:'Critical',criterion:'동일 10분 관찰 구간의 비정상 통신 수',before:8,after:0,unit:'건',evidence:'EC2에서 알려진 의심 목적지로 반복 통신이 관찰되었습니다. 공격 출발지 위치 정보는 없습니다.',recommendation:'연결 근거를 검토한 뒤 해당 목적지 통신을 차단하고 재관찰합니다.',mode:'수동'},
  {scenario:'NMS-01',title:'EC2 CPU 사용률 80% 초과',source:'CloudWatch',severity:'Medium',criterion:'동일 5분 평균 CPU 사용률',before:86,after:58,unit:'%',evidence:'5분 평균 CPU 사용률 86%가 임계치 80%를 초과했습니다.',recommendation:'부하 프로세스를 확인하고 조정 후 5분 평균을 재확인합니다.',mode:'수동'},
  {scenario:'SEC-04',title:'패키지 취약점 업데이트 필요',source:'Inspector',severity:'Low',criterion:'동일 패키지 집합의 미해결 취약점 수',before:4,after:0,unit:'개',evidence:'인스턴스 패키지 점검에서 업데이트가 필요한 항목 4개를 발견했습니다.',recommendation:'승인된 패키지를 업데이트하고 동일 패키지 집합을 점검합니다.',mode:'수동'},
  {scenario:'NMS-02',title:'EC2 메모리 사용률 80% 초과',source:'CloudWatch',severity:'High',criterion:'동일 5분 평균 메모리 사용률',before:84,after:63,unit:'%',evidence:'CloudWatch Agent의 메모리 사용률 평균이 84%입니다.',recommendation:'메모리 사용 프로세스를 확인하고 조정 후 재점검합니다.',mode:'수동'},
];
export function createEvents(){
 return regions.flatMap((r,ri)=>Array.from({length:ri===0?24:ri===5?5:12},(_,i)=>{
  const s=ri===5?{scenario:'IAM-01',title:'글로벌 IAM 역할 신뢰 정책 검토',source:'Security Hub',severity:'High',criterion:'승인되지 않은 외부 계정 신뢰 항목 수',before:1,after:0,unit:'개',evidence:'글로벌 IAM 역할의 신뢰 정책에 검토가 필요한 외부 계정 항목이 있습니다. 지리 좌표가 없는 데모 탐지입니다.',recommendation:'신뢰 관계의 업무 필요성을 검토하고 승인되지 않은 계정 항목을 제거합니다.',mode:'수동'}:scenarios[(i+ri)%scenarios.length];
  const age=[.12,.3,.55,.8,1.2,2,3,4,5,7,9,11,13,15,17,20,23,30,40,50,65,80,110,145][i];
  const at=DEMO_NOW-age*3600000;
  const status=i%7===6?'해결':i%7===5?'재검증 실패':s.mode==='자동'?'신규':'승인 대기';
  const resource=ri===5?'arn:aws:iam::demo:role/shared':s.scenario==='SEC-03'?`sg-${r.id}-db`:s.source==='Trivy'?`ecr/${r.id}/app:1.2`:r.resource;
  return {...s,id:`EVT-${String(ri*100+i+1).padStart(4,'0')}`,region:r.id,environment:i%6===5?'staging':'production',resource,at,status,execution:status==='해결'||status==='재검증 실패'?'성공':'미실행',verification:status==='해결'?'통과':status==='재검증 실패'?'실패':'미실행',beforeAt:at,afterAt:status==='해결'||status==='재검증 실패'?at+180000:null,afterValue:status==='해결'?(s.unit==='%'?s.after:0):status==='재검증 실패'?(s.unit==='%'?s.before:s.after||1):null,history:[{at,text:'탐지 근거 수집'},...(status==='해결'||status==='재검증 실패'?[{at:at+60000,text:'데모 조치 실행 성공'},{at:at+180000,text:status==='해결'?'재검증 통과':'재검증 실패 · 미해결 항목 존재'}]:[])]};
 }));
}
export function metricsFor(region,hours,endOffset=0,environment='production'){
 if(!region?.resource)return null;
 const n=regions.findIndex(r=>r.id===region.id);
 const atOffset=offset=>{const k=Math.floor(offset)%12;const env=environment==='staging'?-12:0;return {cpu:[58,61,64,68,73,81,86,65,57,44,47,42][k]+n*2+env,memory:[63,65,66,71,76,84,68,63,59,55,54,51][k]+n+env};};
 return {resource:region.resource,...atOffset(endOffset),at:DEMO_NOW-endOffset*3600000,points:Array.from({length:12},(_,i)=>{const offset=endOffset+(11-i)*hours/11;return {at:DEMO_NOW-offset*3600000,...atOffset(offset)};})};
}
