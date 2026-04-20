# 모니터링 및 운영 기준

AWS 엔터프라이즈 아키텍처 문서의 모니터링/운영 섹션 작성 기준입니다.

---

## 1. 핵심 모니터링 서비스

| 서비스 | 용도 | 필수 여부 |
|--------|------|---------|
| CloudTrail | API 감사 로그 | 모든 계정 필수 |
| Config | 리소스 변경 추적 | 필수 |
| CloudWatch | 지표/알람 | 서비스별 |
| GuardDuty | 위협 탐지 | 필수 |
| Security Hub | 통합 보안 점수 | 필수 |

## 2. CloudWatch 알람 패턴

```hcl
resource "aws_cloudwatch_metric_alarm" "example" {
  alarm_name          = "<NAME>"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "<METRIC>"
  namespace           = "<NAMESPACE>"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
```

## 3. 크로스 계정 모니터링 (OAM)

```bash
# OAM Sink (중앙 모니터링 계정)
aws oam create-sink --name "central-monitoring"

# OAM Link (각 워크로드 계정)
aws oam create-link \
  --label-template "$AccountName" \
  --resource-types "AWS::CloudWatch::Metric" "AWS::Logs::LogGroup" \
  --sink-identifier <SINK_ARN>
```

## 4. 비용 이상 탐지

```bash
aws ce create-anomaly-subscription \
  --anomaly-subscription '{
    "SubscriptionName": "daily-cost-alert",
    "MonitorArnList": ["<MONITOR_ARN>"],
    "Subscribers": [{"Address": "<EMAIL>", "Type": "EMAIL"}],
    "Threshold": 20,
    "Frequency": "DAILY"
  }'
```

## 5. 문서별 모니터링 포인트

- **네트워크**: VPC Flow Logs, TGW 지표, DX 연결 상태
- **보안**: GuardDuty 발견 사항, Config 위반, CloudTrail 이상 API
- **비용**: Budget 알람, Cost Anomaly Detection
