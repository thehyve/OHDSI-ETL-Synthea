/* Build temp table that populatve visit_occurrence, using logic from:
 *
 * https://github.com/OHDSI/ETL-HealthVerityBuilder/blob/master/inst/sql/sql_server/AllVisitTable.sql
 *
 */



IF OBJECT_ID('tempdb..#IP_VISITS', 'U') IS NOT NULL DROP TABLE #IP_VISITS;

CREATE TABLE #IP_VISITS WITH (LOCATION = USER_DB, DISTRIBUTION = HASH(HVID)) AS
WITH CTE_END_DATES AS (
	SELECT patient, encounterclass, EVENT_DATE-1 AS END_DATE
	FROM (
		SELECT patient, encounterclass, EVENT_DATE, EVENT_TYPE,
			MAX(START_ORDINAL) OVER (PARTITION BY patient, encounterclass ORDER BY EVENT_DATE, EVENT_TYPE ROWS UNBOUNDED PRECEDING) AS START_ORDINAL,
			ROW_NUMBER() OVER (PARTITION BY patient, encounterclass ORDER BY EVENT_DATE, EVENT_TYPE) AS OVERALL_ORD
		FROM (
			SELECT patient, encounterclass, start AS EVENT_DATE, -1 AS EVENT_TYPE, 
			       ROW_NUMBER () OVER (PARTITION BY patient, encounterclass ORDER BY start, stop) AS START_ORDINAL
			FROM encounters
			WHERE encounterclass = 'inpatient'
			UNION ALL
			SELECT patient, encounterclass, stop+1, 1 AS EVENT_TYPE, NULL
			FROM encounters
			WHERE encounterclass = 'inpatient'
		) RAWDATA
	) E
	WHERE (2 * E.START_ORDINAL - E.OVERALL_ORD = 0)
),
CTE_VISIT_ENDS AS (
	SELECT V.patient,
		V.encounterclass,
		V.start VISIT_START_DATE,
		MIN(E.END_DATE) AS VISIT_END_DATE
	FROM encounters V
		JOIN CTE_END_DATES E
			ON V.patient = E.patient
			AND V.encounterclass = E.encounterclass
			AND E.END_DATE >= V.start
	GROUP BY V.patient,V.encounterclass,V.start
)
SELECT T2.patient,
	T2.encounterclass,
	T2.VISIT_START_DATE,
	T2.VISIT_END_DATE
FROM (
	SELECT patient,
		encounterclass,
		MIN(VISIT_START_DATE) AS VISIT_START_DATE,
		VISIT_END_DATE,
		COUNT(*) AS CLAIM_LINE_COUNT
	FROM CTE_VISIT_ENDS
	GROUP BY patient, encounterclass, VISIT_END_DATE
) T2;



IF OBJECT_ID('tempdb..#ER_VISITS', 'U') IS NOT NULL DROP TABLE #ER_VISITS;

CREATE TABLE #ER_VISITS WITH (LOCATION = USER_DB, DISTRIBUTION = HASH(HVID)) AS
SELECT T2.patient,
	T2.encounterclass,
	T2.VISIT_START_DATE,
	T2.VISIT_END_DATE
FROM (
	SELECT patient,
		encounterclass,
		VISIT_START_DATE,
		MAX(VISIT_END_DATE) AS VISIT_END_DATE
	FROM (
		SELECT CL1.patient,
			CL1.encounterclass,
			CL1.start VISIT_START_DATE,
			CL2.stop VISIT_END_DATE
		FROM encounters CL1
		JOIN encounters CL2
			ON CL1.patient = CL2.patient
			AND CL1.start = CL2.start
			AND CL1.encounterclass = CL2.encounterclass
		WHERE CL1.encounterclass in ('emergency','urgent')
	) T1
	GROUP BY patient, encounterclass, VISIT_START_DATE
) T2;



IF OBJECT_ID('tempdb..#OP_VISITS', 'U') IS NOT NULL DROP TABLE #OP_VISITS;

CREATE TABLE #OP_VISITS WITH (LOCATION = USER_DB, DISTRIBUTION = HASH(HVID)) AS
WITH CTE_VISITS_DISTINCT AS (
	SELECT DISTINCT patient,
					encounterclass,
					start VISIT_START_DATE,
					stop VISIT_END_DATE
	FROM encounters
	WHERE encounterclass in ('ambulatory', 'wellness', 'outpatient')
)
SELECT patient,
		encounterclass,
		VISIT_START_DATE,
		MAX(VISIT_END_DATE) AS VISIT_END_DATE
FROM CTE_VISITS_DISTINCT
GROUP BY patient, encounterclass, VISIT_START_DATE;



IF OBJECT_ID('tempdb..@result_temp_all_visits', 'U') IS NOT NULL DROP TABLE @result_temp_all_visits;

CREATE TABLE @result_temp_all_visits WITH (LOCATION = USER_DB, DISTRIBUTION = HASH(HVID)) AS
  SELECT *
  FROM
  (
  	SELECT * FROM #IP_VISITS
  	UNION ALL
  	SELECT * FROM #ER_VISITS
  	UNION ALL
  	SELECT * FROM #OP_VISITS
  ) T1;


