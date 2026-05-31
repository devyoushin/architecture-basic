# CDN Logs Insights Queries

## 1. Cache Miss 상위 URI

```sql
fields @timestamp, cs_uri_stem, cs_uri_query, x_edge_result_type, sc_status
| filter x_edge_result_type like /Miss|RefreshHit|OriginShieldMiss/
| stats count(*) as misses by cs_uri_stem
| sort misses desc
| limit 50
```

## 2. Cache Hit Ratio 추이

```sql
fields @timestamp, x_edge_result_type
| stats count(*) as requests,
        sum(if(x_edge_result_type = "Hit", 1, 0)) as hits,
        sum(if(x_edge_result_type != "Hit", 1, 0)) as non_hits
  by bin(5m)
| sort bin(5m) asc
```

## 3. Origin 5xx 상위 URI

```sql
fields @timestamp, cs_uri_stem, sc_status, x_edge_result_type, time_taken
| filter sc_status >= 500
| stats count(*) as errors,
        pct(time_taken, 95) as p95_time_taken
  by cs_uri_stem, sc_status
| sort errors desc
| limit 50
```

## 4. Query String으로 Cache Key가 분산되는 URI

```sql
fields @timestamp, cs_uri_stem, cs_uri_query
| filter cs_uri_query != "-"
| stats count_distinct(cs_uri_query) as query_variants,
        count(*) as requests
  by cs_uri_stem
| filter query_variants > 100
| sort query_variants desc
| limit 50
```

## 5. 게임 패치 파일 다운로드 상위 Object

```sql
fields @timestamp, cs_uri_stem, sc_bytes, x_edge_result_type
| filter cs_uri_stem like /\/patch\//
| stats count(*) as requests,
        sum(sc_bytes) / 1024 / 1024 / 1024 as gb_sent,
        sum(if(x_edge_result_type = "Hit", 1, 0)) as hits
  by cs_uri_stem
| sort gb_sent desc
| limit 50
```

## 6. 영상 Segment 요청 분석

```sql
fields @timestamp, cs_uri_stem, sc_status, time_taken, x_edge_result_type
| filter cs_uri_stem like /\.m4s$/ or cs_uri_stem like /\.ts$/
| stats count(*) as requests,
        pct(time_taken, 95) as p95_time_taken,
        sum(if(x_edge_result_type = "Hit", 1, 0)) as hits
  by cs_uri_stem
| sort requests desc
| limit 50
```

## 7. Signed URL/Cookie 오류 추적

```sql
fields @timestamp, cs_uri_stem, sc_status, x_edge_detailed_result_type
| filter sc_status = 403
| stats count(*) as denied by x_edge_detailed_result_type, cs_uri_stem
| sort denied desc
| limit 50
```
