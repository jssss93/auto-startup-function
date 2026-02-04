import logging
import os
import json
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.core.exceptions import AzureError
import azure.functions as func

logger = logging.getLogger(__name__)


def get_azure_credential():
    """
    Azure 인증 자격 증명을 가져옵니다.
    Managed Identity가 있으면 사용하고, 없으면 DefaultAzureCredential을 사용합니다.
    """
    try:
        # Managed Identity (Azure Function에서 실행 시)
        return ManagedIdentityCredential()
    except Exception:
        # 로컬 개발 환경에서는 DefaultAzureCredential 사용
        # (Azure CLI, Visual Studio Code, 환경 변수 등에서 자격 증명을 찾음)
        return DefaultAzureCredential()


def get_vm_status(compute_client: ComputeManagementClient, resource_group: str, vm_name: str):
    """
    VM의 현재 상태를 확인합니다.
    
    Returns:
        str: VM의 상태 ('running', 'stopped', 'deallocated', 'unknown')
    """
    try:
        vm_instance_view = compute_client.virtual_machines.instance_view(
            resource_group_name=resource_group,
            vm_name=vm_name
        )
        
        # VM 상태 확인
        if vm_instance_view.statuses:
            for status in vm_instance_view.statuses:
                if status.code.startswith('PowerState/'):
                    power_state = status.code.split('/')[1].lower()
                    return power_state
        
        return 'unknown'
    except AzureError as e:
        logger.error(f"VM 상태 확인 중 오류 발생: {str(e)}")
        raise


def start_vm(compute_client: ComputeManagementClient, resource_group: str, vm_name: str):
    """
    VM을 시작합니다.
    
    Returns:
        bool: 시작 성공 여부
    """
    try:
        # VM 시작
        logger.info(f"VM '{vm_name}' 시작 중...")
        poller = compute_client.virtual_machines.begin_start(
            resource_group_name=resource_group,
            vm_name=vm_name
        )
        poller.wait()  # 시작 완료 대기
        
        logger.info(f"VM '{vm_name}' 시작 완료")
        return True
    except AzureError as e:
        logger.error(f"VM 시작 중 오류 발생: {str(e)}")
        return False


def process_vm(compute_client: ComputeManagementClient, subscription_id: str, vm_name: str, resource_group: str):
    """
    단일 VM을 처리합니다.
    
    Args:
        compute_client: Compute Management Client
        subscription_id: Azure 구독 ID
        vm_name: VM 이름
        resource_group: 리소스 그룹 이름
    
    Returns:
        bool: 처리 성공 여부
    """
    try:
        logger.info(f"[{vm_name}] VM 상태 확인 중... (리소스 그룹: {resource_group})")
        vm_status = get_vm_status(compute_client, resource_group, vm_name)
        logger.info(f"[{vm_name}] 현재 상태: {vm_status}")
        
        # VM이 이미 실행 중이면 스킵
        if vm_status == 'running':
            logger.info(f"[{vm_name}] 이미 실행 중입니다. 작업을 건너뜁니다.")
            return True
        
        # VM이 stopped 또는 deallocated 상태면 시작
        if vm_status in ['stopped', 'stopped (deallocated)', 'deallocated']:
            success = start_vm(compute_client, resource_group, vm_name)
            if success:
                logger.info(f"[{vm_name}] 시작 작업이 성공적으로 완료되었습니다.")
                return True
            else:
                logger.error(f"[{vm_name}] 시작 작업이 실패했습니다.")
                return False
        else:
            logger.warning(f"[{vm_name}] 상태가 예상과 다릅니다: {vm_status}. 작업을 건너뜁니다.")
            return True
    
    except Exception as e:
        logger.error(f"[{vm_name}] 처리 중 오류 발생: {str(e)}", exc_info=True)
        return False


def parse_vm_list():
    """
    환경 변수에서 VM 목록을 파싱합니다.
    
    Returns:
        list: VM 정보 딕셔너리 리스트 [{'name': 'vm-name', 'resource_group': 'rg-name'}, ...]
    """
    # 방법 1: JSON 형식으로 여러 VM 저장 (권장)
    vm_list_json = os.environ.get('AZURE_VM_LIST')
    if vm_list_json:
        try:
            vm_list = json.loads(vm_list_json)
            if isinstance(vm_list, list):
                return vm_list
            else:
                logger.warning("AZURE_VM_LIST가 리스트 형식이 아닙니다. 단일 VM 형식으로 처리합니다.")
        except json.JSONDecodeError as e:
            logger.error(f"AZURE_VM_LIST JSON 파싱 오류: {str(e)}")
            raise ValueError(f"AZURE_VM_LIST JSON 형식이 올바르지 않습니다: {str(e)}")
    
    # 방법 2: 단일 VM 형식 (하위 호환성)
    vm_name = os.environ.get('AZURE_VM_NAME')
    resource_group = os.environ.get('AZURE_RESOURCE_GROUP')
    if vm_name and resource_group:
        logger.info("단일 VM 형식으로 처리합니다.")
        return [{'name': vm_name, 'resource_group': resource_group}]
    
    # 환경 변수가 없으면 오류
    raise ValueError(
        "VM 목록이 설정되지 않았습니다. "
        "AZURE_VM_LIST (JSON 배열) 또는 AZURE_VM_NAME/AZURE_RESOURCE_GROUP을 설정하세요."
    )


def main(myTimer: func.TimerRequest) -> None:
    """
    Timer Trigger의 메인 함수
    매일 20시(저녁 8시)에 실행되어 shutdown된 VM들을 시작합니다.
    """
    if myTimer.past_due:
        logger.warning('Timer function이 예정된 시간보다 늦게 실행되었습니다.')
    
    logger.info(f'VM 자동 시작 함수가 실행되었습니다. (Timer: {myTimer.past_due})')
    
    # 환경 변수에서 설정 읽기
    subscription_id = os.environ.get('AZURE_SUBSCRIPTION_ID')
    
    # 필수 환경 변수 확인
    if not subscription_id:
        error_msg = "필수 환경 변수가 설정되지 않았습니다: AZURE_SUBSCRIPTION_ID"
        logger.error(error_msg)
        raise ValueError(error_msg)
    
    # VM 목록 파싱
    try:
        vm_list = parse_vm_list()
        logger.info(f"처리할 VM 개수: {len(vm_list)}")
        for vm_info in vm_list:
            logger.info(f"  - {vm_info.get('name')} ({vm_info.get('resource_group')})")
    except ValueError as e:
        logger.error(str(e))
        raise
    
    try:
        # Azure 인증
        logger.info("Azure 인증 중...")
        credential = get_azure_credential()
        
        # Compute Management Client 생성
        compute_client = ComputeManagementClient(credential, subscription_id)
        
        # 각 VM 처리
        success_count = 0
        fail_count = 0
        
        for vm_info in vm_list:
            vm_name = vm_info.get('name')
            resource_group = vm_info.get('resource_group')
            
            if not vm_name or not resource_group:
                logger.error(f"VM 정보가 올바르지 않습니다: {vm_info}")
                fail_count += 1
                continue
            
            logger.info(f"\n{'='*60}")
            logger.info(f"VM 처리 시작: {vm_name}")
            logger.info(f"{'='*60}")
            
            success = process_vm(compute_client, subscription_id, vm_name, resource_group)
            if success:
                success_count += 1
            else:
                fail_count += 1
        
        # 결과 요약
        logger.info(f"\n{'='*60}")
        logger.info(f"처리 완료: 성공 {success_count}개, 실패 {fail_count}개 (총 {len(vm_list)}개)")
        logger.info(f"{'='*60}")
        
        if fail_count > 0:
            raise Exception(f"{fail_count}개의 VM 처리에 실패했습니다.")
    
    except Exception as e:
        logger.error(f"VM 자동 시작 중 오류 발생: {str(e)}", exc_info=True)
        raise
