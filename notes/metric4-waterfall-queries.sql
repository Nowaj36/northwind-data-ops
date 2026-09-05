-- METRIC 4 — Q3 baseline as-is, reported "28 of 91 days flagged"
WITH daily AS (
    SELECT n.submitted_at_utc::date AS submit_day, COUNT(*) AS notes
    FROM note n
    WHERE n.submitted_at_utc::date BETWEEN DATE '2026-04-01' AND DATE '2026-06-30'
    GROUP BY 1
),
flagged AS (
  SELECT submit_day, notes,
      AVG(notes) OVER (ORDER BY submit_day ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) AS trailing_avg,
      CASE WHEN notes < 0.70 * AVG(notes) OVER (ORDER BY submit_day
                                                ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING)
           THEN 'ANOMALY' END AS flag
  FROM daily
)
SELECT COUNT(*) AS days_in_window,
       SUM(CASE WHEN flag = 'ANOMALY' THEN 1 ELSE 0 END) AS days_flagged
FROM flagged;



-- METRIC 4 — weekday/weekend split: 2 weekday / 26 weekend
WITH daily AS (
    SELECT n.submitted_at_utc::date AS submit_day, COUNT(*) AS notes
    FROM note n
    WHERE n.submitted_at_utc::date BETWEEN DATE '2026-04-01' AND DATE '2026-06-30'
    GROUP BY 1
),
flagged AS (
  SELECT submit_day, notes,
      AVG(notes) OVER (ORDER BY submit_day ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) AS trailing_avg,
      CASE WHEN notes < 0.70 * AVG(notes) OVER (ORDER BY submit_day
                                                ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING)
           THEN 'ANOMALY' END AS flag
  FROM daily
)
SELECT
  CASE WHEN EXTRACT(DOW FROM submit_day) IN (0,6) THEN 'weekend' ELSE 'weekday' END AS day_type,
  COUNT(*) AS days_flagged
FROM flagged
WHERE flag = 'ANOMALY'
GROUP BY 1;




-- METRIC 4 — TRUE: 2 anomalies, 65 weekdays, 56 evaluable
WITH deduped_note AS (
  SELECT DISTINCT ON (note_id) * FROM note ORDER BY note_id, ingested_at_utc DESC
),
daily AS (
  SELECT (submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date AS submit_day,
         COUNT(*) AS notes
  FROM deduped_note
  WHERE is_void = false
  GROUP BY 1
),
weekdays_only AS (
  SELECT * FROM daily
  WHERE EXTRACT(DOW FROM submit_day) BETWEEN 1 AND 5
),
flagged AS (
  SELECT submit_day, notes,
     ROUND(AVG(notes) OVER (ORDER BY submit_day ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING), 1) AS trailing_avg,
     COUNT(*)   OVER (ORDER BY submit_day ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) AS window_size,
     CASE WHEN COUNT(*) OVER (ORDER BY submit_day ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) = 14
           AND notes < 0.70 * AVG(notes) OVER (ORDER BY submit_day
                                               ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING)
          THEN 'ANOMALY' END AS flag
  FROM weekdays_only
)
SELECT COUNT(*) AS weekdays_in_quarter,
       SUM(CASE WHEN window_size = 14 THEN 1 ELSE 0 END) AS days_evaluable,
       SUM(CASE WHEN flag = 'ANOMALY' THEN 1 ELSE 0 END) AS genuine_anomalies
FROM flagged
WHERE submit_day BETWEEN DATE '2026-04-01' AND DATE '2026-06-30';