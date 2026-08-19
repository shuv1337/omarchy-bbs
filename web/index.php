<?php
declare(strict_types=1);

const SESSION_TTL = 2592000;
const LOGIN_WINDOW = 90;
$configPath = getenv('OMARCHY_BBS_CONFIG') ?: dirname(__DIR__, 2).'/.config/omarchy-bbs.php';
if (!is_file($configPath)) { http_response_code(503); exit('BBS is not configured.'); }
$config = require $configPath;

function db(): PDO {
  static $pdo; global $config;
  if (!$pdo) $pdo = new PDO("mysql:host={$config['db_host']};dbname={$config['db_name']};charset=utf8mb4", $config['db_user'], $config['db_pass'], [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,PDO::ATTR_EMULATE_PREPARES=>false]);
  return $pdo;
}
function migrate(): void { db()->exec(<<<'SQL'
CREATE TABLE IF NOT EXISTS users (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,handle VARCHAR(32) NOT NULL UNIQUE,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS devices (id VARCHAR(64) PRIMARY KEY,user_id BIGINT UNSIGNED NOT NULL,secret_enc TEXT NOT NULL,omarchy_version VARCHAR(80) NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,last_seen_at DATETIME NULL,FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS sessions (token_hash CHAR(64) PRIMARY KEY,user_id BIGINT UNSIGNED NOT NULL,csrf_token CHAR(64) NOT NULL,theme_json TEXT NOT NULL,expires_at DATETIME NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,INDEX(expires_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS login_nonces (nonce_hash CHAR(64) PRIMARY KEY,expires_at DATETIME NOT NULL,INDEX(expires_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS registrations (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,ip_hash CHAR(64) NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,INDEX(ip_hash,created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS action_log (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,user_id BIGINT UNSIGNED NOT NULL,action_kind VARCHAR(24) NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,INDEX(user_id,action_kind,created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS threads (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,user_id BIGINT UNSIGNED NOT NULL,category VARCHAR(24) NOT NULL DEFAULT 'general',title_enc TEXT NOT NULL,body_enc MEDIUMTEXT NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,INDEX(category,created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS replies (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,thread_id BIGINT UNSIGNED NOT NULL,user_id BIGINT UNSIGNED NOT NULL,parent_reply_id BIGINT UNSIGNED NULL,body_enc MEDIUMTEXT NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,FOREIGN KEY(thread_id) REFERENCES threads(id) ON DELETE CASCADE,FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,INDEX(parent_reply_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQL);
  $columns=[];foreach(db()->query('SHOW COLUMNS FROM threads') as $row)$columns[$row['Field']]=true;
  if(!isset($columns['category']))db()->exec("ALTER TABLE threads ADD category VARCHAR(24) NOT NULL DEFAULT 'general' AFTER user_id, ADD INDEX(category,created_at)");
  $columns=[];foreach(db()->query('SHOW COLUMNS FROM replies') as $row)$columns[$row['Field']]=true;
  if(!isset($columns['parent_reply_id']))db()->exec('ALTER TABLE replies ADD parent_reply_id BIGINT UNSIGNED NULL AFTER user_id, ADD INDEX(parent_reply_id)');
}
function categories(): array { return ['general','projects','help','showcase','meta']; }
function j(int $status,array $data): never { http_response_code($status); header('Content-Type: application/json'); header('Cache-Control: no-store'); echo json_encode($data); exit; }
function go(string $url): never { header('Location: '.$url,true,303); exit; }
function e(mixed $value): string { return htmlspecialchars((string)$value,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8'); }
function seal(string $plaintext): string {
  global $config; $key=hex2bin($config['app_key']);
  if($key===false||strlen($key)!==SODIUM_CRYPTO_SECRETBOX_KEYBYTES)throw new RuntimeException('Invalid encryption key');
  $nonce=random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
  return base64_encode($nonce.sodium_crypto_secretbox($plaintext,$nonce,$key));
}
function unseal(string $encoded): string {
  global $config; $packed=base64_decode($encoded,true);$key=hex2bin($config['app_key']);
  if($packed===false||$key===false||strlen($packed)<=SODIUM_CRYPTO_SECRETBOX_NONCEBYTES)throw new RuntimeException('Invalid encrypted record');
  $nonce=substr($packed,0,SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);$plain=sodium_crypto_secretbox_open(substr($packed,SODIUM_CRYPTO_SECRETBOX_NONCEBYTES),$nonce,$key);
  if($plain===false)throw new RuntimeException('Encrypted record authentication failed'); return $plain;
}
function user(): ?array {
  $token=$_COOKIE['bbs_session']??''; if(!preg_match('/^[A-Za-z0-9_-]{40,100}$/',$token)) return null;
  $q=db()->prepare('SELECT u.*,s.csrf_token,s.theme_json FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>NOW()'); $q->execute([hash('sha256',$token)]); return $q->fetch()?:null;
}
function mustUser(): array { $u=user(); if(!$u){http_response_code(401);header('Content-Type:text/plain');exit("Open this board from the Omarchy BBS bar widget.\n");} return $u; }
function csrf(array $u): void { if(!isset($_POST['csrf'])||!hash_equals($u['csrf_token'],(string)$_POST['csrf'])){http_response_code(403);exit('Invalid request token.');} }
function throttle(int $userId,string $kind,int $limit): void {
  $q=db()->prepare('SELECT COUNT(*) FROM action_log WHERE user_id=? AND action_kind=? AND created_at>DATE_SUB(NOW(),INTERVAL 10 MINUTE)');$q->execute([$userId,$kind]);
  if((int)$q->fetchColumn()>=$limit){http_response_code(429);exit('Slow down and try again shortly.');}
  db()->prepare('INSERT INTO action_log(user_id,action_kind) VALUES(?,?)')->execute([$userId,$kind]);
}
function page(string $title,array $u,string $content): never {
  $theme=json_decode($u['theme_json']??'',true);$fallback=['bg'=>'#0c0f0d','panel'=>'#151a16','ink'=>'#e8f3e9','muted'=>'#8fa091','hot'=>'#a7f3a0','amber'=>'#f6c177'];if(!is_array($theme))$theme=$fallback;foreach($fallback as $k=>$v)if(!isset($theme[$k])||!preg_match('/^#[0-9a-fA-F]{6}$/',$theme[$k]))$theme[$k]=$v;
  $line=$theme['muted'].'66';$input=$theme['bg'];
  $css=":root{color-scheme:dark;--bg:{$theme['bg']};--panel:{$theme['panel']};--ink:{$theme['ink']};--muted:{$theme['muted']};--line:$line;--hot:{$theme['hot']};--amber:{$theme['amber']};--input:$input}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace}main{width:min(880px,calc(100% - 28px));margin:auto}.mast{border-bottom:1px solid var(--line);padding:28px 0 18px;display:flex;justify-content:space-between;align-items:end}.brand{font-size:clamp(24px,6vw,48px);font-weight:900;letter-spacing:-.08em;color:var(--hot)}.tag,.meta{color:var(--muted);font-size:13px}.nav{padding:14px 0;display:flex;gap:18px}.nav a,a{color:var(--hot);text-decoration:none}.card{background:var(--panel);border:1px solid var(--line);border-radius:8px;margin:14px 0;padding:18px}.thread{display:grid;grid-template-columns:1fr auto;gap:8px}.thread h2{font-size:18px;margin:0}.body{white-space:pre-wrap;margin-top:12px}form{display:grid;gap:10px}input,textarea,button{font:inherit;color:var(--ink);background:var(--input);border:1px solid var(--line);border-radius:5px;padding:10px}textarea{min-height:110px;resize:vertical}button{width:max-content;background:var(--hot);color:var(--bg);border:0;font-weight:800;cursor:pointer}.badge{color:var(--amber)}footer{color:var(--muted);padding:30px 0 50px;text-align:center}@media(max-width:560px){.mast{align-items:start;flex-direction:column;gap:8px}.thread{grid-template-columns:1fr}}";
  header("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"); header('X-Content-Type-Options:nosniff');
  echo '<!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1"><title>'.e($title).' · Omarchy BBS</title><style>'.$css.'</style></head><body><main><header class=mast><div><div class=brand>OMARCHY//BBS</div><div class=tag>Community discussion board</div></div><div class=meta>Signed in as <span class=badge>@'.e($u['handle']).'</span></div></header><nav class=nav><a href=/>[ posts ]</a><a href=/new>[ new post ]</a><a href=/logout>[ sign out ]</a></nav>'.$content.'<footer>ENCRYPTED OMARCHY BBS</footer></main></body></html>'; exit;
}
function registerDevice(): never {
  global $config; $in=json_decode(file_get_contents('php://input'),true); if(!is_array($in)) j(400,['error'=>'Invalid JSON']);
  $device=(string)($in['device_id']??'');$secret=(string)($in['secret']??'');$handle=strtolower(trim((string)($in['handle']??'')));$version=substr(trim((string)($in['omarchy_version']??'')),0,80);
  if(!preg_match('/^[A-Za-z0-9_-]{16,64}$/',$device)||!preg_match('/^[a-f0-9]{64}$/',$secret)||!preg_match('/^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$/',$handle)||$version==='') j(400,['error'=>'Invalid Omarchy identity']);
  $ip=hash_hmac('sha256',$_SERVER['REMOTE_ADDR']??'unknown',$config['app_key']);$pdo=db();$q=$pdo->prepare('SELECT COUNT(*) FROM registrations WHERE ip_hash=? AND created_at>DATE_SUB(NOW(),INTERVAL 1 HOUR)');$q->execute([$ip]);if((int)$q->fetchColumn()>=10)j(429,['error'=>'Too many registrations']);
  try{$pdo->beginTransaction();$pdo->prepare('INSERT INTO users(handle) VALUES(?)')->execute([$handle]);$uid=(int)$pdo->lastInsertId();$pdo->prepare('INSERT INTO devices(id,user_id,secret_enc,omarchy_version) VALUES(?,?,?,?)')->execute([$device,$uid,seal($secret),$version]);$pdo->prepare('INSERT INTO registrations(ip_hash) VALUES(?)')->execute([$ip]);$pdo->commit();}catch(PDOException $x){if($pdo->inTransaction())$pdo->rollBack();if((string)$x->getCode()==='23000')j(409,['error'=>'Identity already exists']);throw $x;}
  j(201,['device_id'=>$device,'handle'=>$handle]);
}
function apiInput(): array {
  $in=json_decode(file_get_contents('php://input'),true);if(!is_array($in))j(400,['error'=>'Invalid JSON']);return $in;
}
function apiDevice(array $in,string $purpose,bool $consumeNonce=true): array {
  $d=(string)($in['device']??'');$ts=(string)($in['ts']??'');$n=(string)($in['nonce']??'');$sig=(string)($in['sig']??'');
  if(!ctype_digit($ts)||abs(time()-(int)$ts)>LOGIN_WINDOW||!preg_match('/^[A-Za-z0-9_-]{8,64}$/',$n))j(401,['error'=>'Expired device proof']);
  $q=db()->prepare('SELECT d.user_id,d.secret_enc,COALESCE(d.last_seen_at,d.created_at) seen,u.handle FROM devices d JOIN users u ON u.id=d.user_id WHERE d.id=?');$q->execute([$d]);$row=$q->fetch();
  $secret=$row?hex2bin(unseal($row['secret_enc'])):false;$expected=$secret?hash_hmac('sha256',"$d.$ts.$n.$purpose",$secret):'';
  if(!$row||!hash_equals($expected,$sig))j(401,['error'=>'Invalid device proof']);
  if($consumeNonce){try{db()->prepare('INSERT INTO login_nonces(nonce_hash,expires_at) VALUES(?,DATE_ADD(NOW(),INTERVAL 2 MINUTE))')->execute([hash('sha256',$n)]);}catch(PDOException){j(401,['error'=>'Device proof already used']);}}
  $row['device_id']=$d;return $row;
}
function apiThreads(): never {
  $in=apiInput();$u=apiDevice($in,'threads');
  $rows=db()->query('SELECT t.id,t.category,t.title_enc,t.created_at,u.handle,COUNT(r.id) replies FROM threads t JOIN users u ON u.id=t.user_id LEFT JOIN replies r ON r.thread_id=t.id GROUP BY t.id ORDER BY t.id DESC LIMIT 50')->fetchAll();
  $threads=[];foreach($rows as $r)$threads[]=['id'=>(int)$r['id'],'category'=>$r['category'],'title'=>unseal($r['title_enc']),'handle'=>$r['handle'],'created_at'=>$r['created_at'].' UTC','replies'=>(int)$r['replies']];
  db()->prepare('UPDATE devices SET last_seen_at=NOW() WHERE id=?')->execute([$u['device_id']]);j(200,['ok'=>true,'handle'=>$u['handle'],'categories'=>categories(),'threads'=>$threads]);
}
function apiThread(): never {
  $in=apiInput();$id=(int)($in['thread_id']??0);apiDevice($in,'thread:'.$id);
  $q=db()->prepare('SELECT t.id,t.category,t.title_enc,t.body_enc,t.created_at,u.handle FROM threads t JOIN users u ON u.id=t.user_id WHERE t.id=?');$q->execute([$id]);$t=$q->fetch();if(!$t)j(404,['error'=>'Post not found']);
  $q=db()->prepare('SELECT r.id,r.parent_reply_id,r.body_enc,r.created_at,u.handle FROM replies r JOIN users u ON u.id=r.user_id WHERE r.thread_id=? ORDER BY r.id');$q->execute([$id]);$replies=[];foreach($q as $r)$replies[]=['id'=>(int)$r['id'],'parent_reply_id'=>$r['parent_reply_id']===null?null:(int)$r['parent_reply_id'],'body'=>unseal($r['body_enc']),'handle'=>$r['handle'],'created_at'=>$r['created_at'].' UTC'];
  j(200,['ok'=>true,'thread'=>['id'=>(int)$t['id'],'category'=>$t['category'],'title'=>unseal($t['title_enc']),'body'=>unseal($t['body_enc']),'handle'=>$t['handle'],'created_at'=>$t['created_at'].' UTC','replies'=>$replies]]);
}
function apiCreate(): never {
  $in=apiInput();$category=strtolower(trim((string)($in['category']??'general')));$title=trim((string)($in['title']??''));$body=trim((string)($in['body']??''));$digest=hash('sha256',$category."\0".$title."\0".$body);$u=apiDevice($in,'create:'.$digest);
  if(!in_array($category,categories(),true))j(400,['error'=>'Invalid board category']);if($title===''||$body==='')j(400,['error'=>'Title and message are required']);if(mb_strlen($title)>120||mb_strlen($body)>8000)j(400,['error'=>'Post is too long']);throttle((int)$u['user_id'],'thread',10);
  $q=db()->prepare('INSERT INTO threads(user_id,category,title_enc,body_enc) VALUES(?,?,?,?)');$q->execute([$u['user_id'],$category,seal($title),seal($body)]);j(201,['ok'=>true,'thread_id'=>(int)db()->lastInsertId()]);
}
function apiReply(): never {
  $in=apiInput();$id=(int)($in['thread_id']??0);$parent=(int)($in['parent_reply_id']??0);$body=trim((string)($in['body']??''));$u=apiDevice($in,'reply:'.$id.':'.$parent.':'.hash('sha256',$body));
  if($id<1||$body==='')j(400,['error'=>'Reply is required']);if(mb_strlen($body)>8000)j(400,['error'=>'Reply is too long']);$q=db()->prepare('SELECT 1 FROM threads WHERE id=?');$q->execute([$id]);if(!$q->fetchColumn())j(404,['error'=>'Post not found']);throttle((int)$u['user_id'],'reply',30);
  if($parent>0){$q=db()->prepare('SELECT 1 FROM replies WHERE id=? AND thread_id=?');$q->execute([$parent,$id]);if(!$q->fetchColumn())j(400,['error'=>'Parent reply is not in this thread']);}
  db()->prepare('INSERT INTO replies(thread_id,user_id,parent_reply_id,body_enc) VALUES(?,?,?,?)')->execute([$id,$u['user_id'],$parent?:null,seal($body)]);j(201,['ok'=>true]);
}
function authenticate(): never {
  $d=(string)($_GET['device']??'');$ts=(string)($_GET['ts']??'');$n=(string)($_GET['nonce']??'');$sig=(string)($_GET['sig']??'');$next=(string)($_GET['next']??'/');$themeToken=(string)($_GET['theme']??'');
  if(!in_array($next,['/','/new'],true)||!preg_match('/^[A-Za-z0-9_-]{20,600}$/',$themeToken)){http_response_code(400);exit('Invalid destination or theme.');}
  $themeJson=base64_decode(strtr($themeToken,'-_','+/').str_repeat('=',(4-strlen($themeToken)%4)%4),true);$theme=json_decode($themeJson?:'',true);$keys=['bg','panel','ink','muted','hot','amber'];if(!is_array($theme)||count($theme)!==count($keys)){http_response_code(400);exit('Invalid theme.');}foreach($keys as $key)if(!isset($theme[$key])||!is_string($theme[$key])||!preg_match('/^#[0-9a-fA-F]{6}$/',$theme[$key])){http_response_code(400);exit('Invalid theme.');}
  if(!ctype_digit($ts)||abs(time()-(int)$ts)>LOGIN_WINDOW||!preg_match('/^[A-Za-z0-9_-]{8,64}$/',$n)){http_response_code(401);exit('Login link expired.');}
  $q=db()->prepare('SELECT user_id,secret_enc FROM devices WHERE id=?');$q->execute([$d]);$row=$q->fetch();$secret=$row?hex2bin(unseal($row['secret_enc'])):false;$expected=$secret?hash_hmac('sha256',"$d.$ts.$n.login:$next:$themeToken",$secret):'';if(!$row||!hash_equals($expected,$sig)){http_response_code(401);exit('Invalid device proof.');}
  try{db()->prepare('INSERT INTO login_nonces(nonce_hash,expires_at) VALUES(?,DATE_ADD(NOW(),INTERVAL 2 MINUTE))')->execute([hash('sha256',$n)]);}catch(PDOException){http_response_code(401);exit('Login link already used.');}
  $token=rtrim(strtr(base64_encode(random_bytes(48)),'+/','-_'),'=');$csrf=bin2hex(random_bytes(32));db()->prepare('INSERT INTO sessions(token_hash,user_id,csrf_token,theme_json,expires_at) VALUES(?,?,?,?,DATE_ADD(NOW(),INTERVAL 30 DAY))')->execute([hash('sha256',$token),$row['user_id'],$csrf,json_encode($theme)]);db()->prepare('UPDATE devices SET last_seen_at=NOW() WHERE id=?')->execute([$d]);setcookie('bbs_session',$token,['expires'=>time()+SESSION_TTL,'path'=>'/','secure'=>true,'httponly'=>true,'samesite'=>'Strict']);go($next);
}
function status(): never {
  $in=apiInput();$row=apiDevice($in,'status');
  $q=db()->prepare('SELECT (SELECT COUNT(*) FROM threads WHERE created_at>? AND user_id<>?)+(SELECT COUNT(*) FROM replies WHERE created_at>? AND user_id<>?)');$q->execute([$row['seen'],$row['user_id'],$row['seen'],$row['user_id']]);j(200,['unread'=>(int)$q->fetchColumn()]);
}

migrate();
header('Strict-Transport-Security: max-age=31536000; includeSubDomains');header('Referrer-Policy: no-referrer');header('Permissions-Policy: camera=(), microphone=(), geolocation=()');header('X-Frame-Options: DENY');
if(random_int(1,100)===1)db()->exec('DELETE FROM sessions WHERE expires_at<NOW();DELETE FROM login_nonces WHERE expires_at<NOW();DELETE FROM registrations WHERE created_at<DATE_SUB(NOW(),INTERVAL 1 DAY);DELETE FROM action_log WHERE created_at<DATE_SUB(NOW(),INTERVAL 1 DAY)');
$path=parse_url($_SERVER['REQUEST_URI'],PHP_URL_PATH)?:'/';$method=$_SERVER['REQUEST_METHOD'];
if($path==='/health')j(200,['ok'=>true,'service'=>'omarchy-bbs']);
if($path==='/api/register'&&$method==='POST')registerDevice();
if($path==='/api/status'&&$method==='POST')status();
if($path==='/api/threads'&&$method==='POST')apiThreads();
if($path==='/api/thread'&&$method==='POST')apiThread();
if($path==='/api/create'&&$method==='POST')apiCreate();
if($path==='/api/reply'&&$method==='POST')apiReply();
if($path==='/auth'&&$method==='GET')authenticate();
$u=mustUser();
if($path==='/logout'){$token=$_COOKIE['bbs_session']??'';if($token)db()->prepare('DELETE FROM sessions WHERE token_hash=?')->execute([hash('sha256',$token)]);setcookie('bbs_session','',['expires'=>1,'path'=>'/','secure'=>true,'httponly'=>true,'samesite'=>'Strict']);go('/');}
if($path==='/'&&$method==='GET'){$rows=db()->query('SELECT t.id,t.title_enc,t.created_at,u.handle,COUNT(r.id) replies FROM threads t JOIN users u ON u.id=t.user_id LEFT JOIN replies r ON r.thread_id=t.id GROUP BY t.id ORDER BY t.id DESC LIMIT 100')->fetchAll();$cards='';foreach($rows as $r)$cards.='<article class="card thread"><div><h2><a href=/thread/'.e($r['id']).'>'.e(unseal($r['title_enc'])).'</a></h2><div class=meta>@'.e($r['handle']).' · '.e($r['created_at']).' UTC</div></div><div class=badge>'.e($r['replies']).' repl.</div></article>';page('Posts',$u,$cards?:'<section class=card>No posts yet.</section>');}
if($path==='/new'&&$method==='GET')page('New post',$u,"<section class=card><h1>New post</h1><form method=post><input type=hidden name=csrf value='".e($u['csrf_token'])."'><input name=title maxlength=120 required placeholder=Subject><textarea name=body maxlength=8000 required placeholder='Write something worth reading.'></textarea><button>Post</button></form></section>");
if($path==='/new'&&$method==='POST'){csrf($u);throttle((int)$u['id'],'thread',10);$title=trim((string)($_POST['title']??''));$body=trim((string)($_POST['body']??''));if($title===''||$body===''){http_response_code(400);exit('Title and body required.');}$q=db()->prepare('INSERT INTO threads(user_id,title_enc,body_enc) VALUES(?,?,?)');$q->execute([$u['id'],seal(mb_substr($title,0,120)),seal(mb_substr($body,0,8000))]);go('/thread/'.db()->lastInsertId());}
if(preg_match('#^/thread/(\d+)$#',$path,$m)){$id=(int)$m[1];if($method==='POST'){csrf($u);throttle((int)$u['id'],'reply',30);$body=trim((string)($_POST['body']??''));if($body===''){http_response_code(400);exit('Reply required.');}db()->prepare('INSERT INTO replies(thread_id,user_id,body_enc) VALUES(?,?,?)')->execute([$id,$u['id'],seal(mb_substr($body,0,8000))]);go('/thread/'.$id);}$q=db()->prepare('SELECT t.*,u.handle FROM threads t JOIN users u ON u.id=t.user_id WHERE t.id=?');$q->execute([$id]);$t=$q->fetch();if(!$t){http_response_code(404);exit('Not found.');}$q=db()->prepare('SELECT r.*,u.handle FROM replies r JOIN users u ON u.id=r.user_id WHERE thread_id=? ORDER BY r.id');$q->execute([$id]);$title=unseal($t['title_enc']);$c='<article class=card><h1>'.e($title).'</h1><div class=meta>@'.e($t['handle']).'</div><div class=body>'.e(unseal($t['body_enc'])).'</div></article>';foreach($q as $r)$c.='<article class=card><div class=meta>@'.e($r['handle']).'</div><div class=body>'.e(unseal($r['body_enc'])).'</div></article>';$c.="<section class=card><form method=post><input type=hidden name=csrf value='".e($u['csrf_token'])."'><textarea name=body maxlength=8000 required placeholder='Write a reply'></textarea><button>Reply</button></form></section>";page($title,$u,$c);}
http_response_code(404);exit('Not found.');
