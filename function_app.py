import azure.functions as func
import logging
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
