import azure.functions as func
import logging
import os
import json
from datetime import datetime

from start_vm import start_vm_timer

app = func.FunctionApp()

@app.timer_trigger(schedule="0 0 20 * * *", arg_name="myTimer", run_on_startup=False,
              use_monitor=False)
def start_vm_timer_function(myTimer: func.TimerRequest) -> None:
    """
    매일 20시(저녁 8시)에 실행되는 Timer Trigger Function
    shutdown된 VM들을 자동으로 시작합니다.
    """
    start_vm_timer.main(myTimer)


@app.function_name(name="HealthCheck")
@app.route(route="health", auth_level=func.AuthLevel.ANONYMOUS)
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """
    헬스체크 엔드포인트
    Function App의 상태를 확인합니다.
    
    사용법:
    - GET: https://<function-app-name>.azurewebsites.net/api/health
    """
    try:
        import platform
        import sys
        
        # VM 개수 안전하게 가져오기
        vm_count = 0
        try:
            if os.environ.get('AZURE_SUBSCRIPTION_ID'):
                vm_count = len(start_vm_timer.parse_vm_list())
        except Exception:
            vm_count = -1  # 파싱 실패
        
        health_status = {
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "service": "azure-function-vm-auto-start",
            "version": "1.0.0",
            "runtime": {
                "python_version": sys.version,
                "platform": platform.platform()
            },
            "environment": {
                "subscription_id": os.environ.get('AZURE_SUBSCRIPTION_ID', 'not_set'),
                "function_app_name": os.environ.get('WEBSITE_SITE_NAME', 'not_set'),
                "vm_count": vm_count
            }
        }
        
        return func.HttpResponse(
            json.dumps(health_status, indent=2),
            status_code=200,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"헬스체크 중 오류 발생: {str(e)}", exc_info=True)
        return func.HttpResponse(
            json.dumps({
                "status": "unhealthy",
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }, indent=2),
            status_code=503,
            mimetype="application/json"
        )


@app.function_name(name="StartVMsManual")
@app.route(route="start-vms", auth_level=func.AuthLevel.FUNCTION)
def start_vms_manual(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP Trigger를 통한 수동 실행 엔드포인트
    테스트 및 수동 실행용
    
    사용법:
    - GET/POST: https://<function-app-name>.azurewebsites.net/api/start-vms?code=<function-key>
    """
    logging.info('수동 실행 요청이 들어왔습니다.')
    
    try:
        # TimerRequest 객체를 시뮬레이션
        class MockTimer:
            past_due = False
        
        mock_timer = MockTimer()
        start_vm_timer.main(mock_timer)
        
        return func.HttpResponse(
            f"VM 시작 작업이 성공적으로 완료되었습니다. (실행 시간: {datetime.now().isoformat()})",
            status_code=200
        )
    except Exception as e:
        logging.error(f"수동 실행 중 오류 발생: {str(e)}", exc_info=True)
        return func.HttpResponse(
            f"VM 시작 작업 중 오류가 발생했습니다: {str(e)}",
            status_code=500
        )
