# 为模拟器提供确定性AI协议夹具，调用真实生产HTTP客户端。
from head import ThreadingHTTPServer, SimpleHTTPRequestHandler, Path, jdmp, jld, ArgumentParser

# 按任务目标返回边界明确的工时和顺序。
class Handler(SimpleHTTPRequestHandler):
 # 不记录凭据或个人内容。
 def log_message(self,*args):pass
 # 接收真实兼容请求并保留模型路由证据。
 def do_POST(self):
  body=jld(self.rfile.read(int(self.headers['Content-Length'])))
  user=jld(body['messages'][-1]['content']);model=body['model']
  with self.server.log.open('a') as output:output.write(jdmp({'model':model,'mode':user.get('mode'),'ddl':user.get('ddl',False),'has_notes':'"notes"' in jdmp(user)})+'\n')
  if user.get('mode')=='order':result={'order':[r['task_id'] for r in reversed(user['tasks'])]}
  else:
   urgent=user.get('ddl',False);total=user.get('total_minutes',45) if urgent else 60 if 'DDL' in user.get('title','') else 30
   minimum=30 if 'DDL' in user.get('title','') else 15
   steps=[{'title':'整理材料','notes':'输出清单','minutes':total}]
   if urgent:steps=[{'title':'先做核心','notes':'核心验收','minutes':20},{'title':'检查提交','notes':'提交成果','minutes':total-20}]
   result={'title':user.get('title','测试'),'notes':'明确成果','minimum_minutes':minimum,'recommended_minutes':60 if minimum==30 else 30,'maximum_minutes':90 if minimum==30 else 60,'difficulty':0,'steps':steps}
  variant=getattr(self.server,'variant','')
  if variant=='range':result['minimum_minutes']=True
  if variant=='sum':result['recommended_minutes']=99
  if variant=='negative':result['steps'][0]['minutes']=-1
  if variant=='duplicate':result['order']=[user['tasks'][0]['task_id']]*len(user['tasks'])
  if variant=='foreign':result['order']=['33333333-3333-4333-8333-999999999999']
  message={'content':jdmp(result)}
  if variant=='tool':message['tool_calls']=[{'name':'execute'}]
  data=jdmp({'model':'silent-fallback' if variant=='model' else model,'choices':[{'message':message}]}).encode()
  self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)

# 启动仅限回环的短期测试服务。
if __name__=='__main__':
 parser=ArgumentParser();parser.add_argument('address');parser.add_argument('log');args=parser.parse_args()
 server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.log=Path(args.log);Path(args.address).write_text(f'http://127.0.0.1:{server.server_port}/v1');server.serve_forever()
