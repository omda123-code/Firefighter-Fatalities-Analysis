use Firefighter
select * from FirefighterDeaths


-- Question What is the total number of fatalities, average and median age
-- Total fatalities, average age, and median age
WITH Base AS (
    SELECT CAST(Age AS FLOAT) AS Age
    FROM FirefighterDeaths
    WHERE Age IS NOT NULL
),
Agg AS (
    SELECT 
        COUNT(*) AS TotalFatalities,
        AVG(Age) AS AvgAge
    FROM Base
)
SELECT 
    Agg.TotalFatalities,
    Agg.AvgAge,
    MedianCalc.MedianAge
FROM Agg
CROSS JOIN (
    SELECT 
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Age) 
        OVER () AS MedianAge
    FROM Base
) AS MedianCalc;



-- Purpose: Trend analysis by incident year.
-- deaths per incident year and YoY change
WITH C AS (
  SELECT *,
    TRY_CONVERT(date, Date_of_Incident, 0) AS IncidentDate
  FROM FirefighterDeaths
)
, Y AS (
  SELECT
    YEAR(IncidentDate) AS IncidentYear,
    COUNT(*) AS Deaths
  FROM C
  WHERE IncidentDate IS NOT NULL
  GROUP BY YEAR(IncidentDate)
)
SELECT
  IncidentYear,
  Deaths,
  Deaths - LAG(Deaths) OVER (ORDER BY IncidentYear) AS YoY_Change,
  CASE WHEN LAG(Deaths) OVER (ORDER BY IncidentYear) = 0 THEN NULL
       ELSE ROUND(100.0*(Deaths - LAG(Deaths) OVER (ORDER BY IncidentYear))/LAG(Deaths) OVER (ORDER BY IncidentYear),2) END AS YoY_Pct_Change
FROM Y
ORDER BY IncidentYear;


-- Top 10 causes of death
-- Purpose: Identify leading causes to prioritize prevention programs.

SELECT TOP (10)
  Cause_Of_Death,
  COUNT(*) AS CountDeaths
FROM FirefighterDeaths
GROUP BY Cause_Of_Death
ORDER BY CountDeaths DESC;


-- Nature of death by duty type (cross-tab)
-- Purpose: Which duties (Response, On-Scene Fire, Training, etc.) have highest proportions of particular natures (e.g., Heart Attack, Stroke).

SELECT
  Duty,
  Nature_Of_Death,
  COUNT(*) AS CountDeaths,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY Duty), 2) AS PctWithinDuty
FROM FirefighterDeaths
GROUP BY Duty, Nature_Of_Death
ORDER BY Duty, CountDeaths DESC;


-- Emergency vs Non-emergency: counts and average age
-- Purpose: Compare fatalities occurring during declared emergencies vs not.

SELECT
  Emergency,
  COUNT(*) AS Deaths,
  AVG(CAST([Age] AS FLOAT)) AS AvgAge
FROM FirefighterDeaths
GROUP BY Emergency
ORDER BY Deaths DESC;


-- Time difference between incident and death (same-day vs delayed)
-- Purpose: Determine how many deaths occur at scene vs later (helps resource planning and reporting).

SELECT
  SUM(CASE WHEN TRY_CONVERT(date,Date_of_Death) IS NOT NULL AND TRY_CONVERT(date,Date_of_Death) IS NOT NULL
           THEN CASE WHEN DATEDIFF(day, TRY_CONVERT(date,[Date_of_Incident]), TRY_CONVERT(date,Date_of_Death)) = 0 THEN 1 ELSE 0 END ELSE 0 END) AS SameDayDeaths,
  SUM(CASE WHEN TRY_CONVERT(date,Date_of_Incident) IS NOT NULL AND TRY_CONVERT(date,Date_of_Death) IS NOT NULL
           THEN CASE WHEN DATEDIFF(day, TRY_CONVERT(date,Date_of_Incident), TRY_CONVERT(date,Date_of_Death)) > 0 THEN 1 ELSE 0 END ELSE 0 END) AS DelayedDeaths,
  AVG(CASE WHEN TRY_CONVERT(date,[Date_of_Incident]) IS NOT NULL AND TRY_CONVERT(date,[Date_of_Death]) IS NOT NULL
           THEN DATEDIFF(day, TRY_CONVERT(date,[Date_of_Incident]), TRY_CONVERT(date,[Date_of_Death])) ELSE NULL END) AS AvgDaysUntilDeath
FROM FirefighterDeaths;


-- Activities associated with highest fatalities (top activities)
-- Purpose: Identify dangerous tasks (Advance Hose Lines, Overhaul, Vehicle operations, etc.).

SELECT TOP (15)
  Activity,
  COUNT(*) AS CountDeaths
FROM dbo.FirefighterDeaths
GROUP BY Activity
ORDER BY CountDeaths DESC;


-- Rank / Classification analysis: Volunteer vs Career
-- Purpose: Compare volunteer vs career firefighter fatality patterns.

SELECT
  Classification,
  COUNT(*) AS Deaths,
  AVG(CAST([Age] AS FLOAT)) AS AvgAge,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CAST([Age] AS FLOAT)) OVER (PARTITION BY Classification) AS MedianAge
FROM FirefighterDeaths
GROUP BY Classification;


-- Property Type vs Cause: correlation table
-- Purpose: Understand what property types (Residential, Street/Road, Outdoor) associate with which causes.

SELECT
  Property_Type,
  [Cause_Of_Death],
  COUNT(*) AS CountDeaths,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY Property_Type),2) AS PctWithinPropertyType
FROM FirefighterDeaths
GROUP BY Property_Type, [Cause_Of_Death]
ORDER BY Property_Type, CountDeaths DESC;


-- Age group distribution (create buckets)
-- Purpose: See which age groups are most affected for targeted health programs.

SELECT
  AgeGroup,
  COUNT(*) AS Deaths
FROM (
  SELECT *,
    CASE
      WHEN TRY_CAST([Age] AS INT) IS NULL THEN 'Unknown'
      WHEN TRY_CAST([Age] AS INT) < 30 THEN '<30'
      WHEN TRY_CAST([Age] AS INT) BETWEEN 30 AND 39 THEN '30-39'
      WHEN TRY_CAST([Age] AS INT) BETWEEN 40 AND 49 THEN '40-49'
      WHEN TRY_CAST([Age] AS INT) BETWEEN 50 AND 59 THEN '50-59'
      WHEN TRY_CAST([Age] AS INT) BETWEEN 60 AND 69 THEN '60-69'
      ELSE '70+' END AS AgeGroup
  FROM dbo.FirefighterDeaths
) t
GROUP BY AgeGroup
ORDER BY CASE AgeGroup WHEN '<30' THEN 1 WHEN '30-39' THEN 2 WHEN '40-49' THEN 3 WHEN '50-59' THEN 4 WHEN '60-69' THEN 5 WHEN '70+' THEN 6 ELSE 7 END;


-- Monthly seasonality (incident month)
-- Purpose: Detect seasonal peaks in incidents (useful for prevention campaigns).

WITH C AS (
  SELECT TRY_CONVERT(date, [Date_of_Incident]) AS IncidentDate FROM dbo.FirefighterDeaths
)
SELECT
  MONTH(IncidentDate) AS IncidentMonth,
  DATENAME(month, DATEADD(month, MONTH(IncidentDate)-1, '2000-01-01')) AS MonthName,
  COUNT(*) AS Deaths
FROM C
WHERE IncidentDate IS NOT NULL
GROUP BY MONTH(IncidentDate)
ORDER BY MONTH(IncidentDate);


-- Most risky combinations (Duty + Activity + Property Type)
-- Purpose: Multi-factor grouping to find high-risk scenario combos.

SELECT TOP (25)
  Duty, Activity, [Property_Type],
  COUNT(*) AS Deaths
FROM dbo.FirefighterDeaths
GROUP BY Duty, Activity, [Property_Type]
ORDER BY Deaths DESC;


-- Average age by Cause of Death (to identify age-skew)
-- Purpose: Which causes hit older firefighters more (e.g., heart attack, stroke).

SELECT
  [Cause_Of_Death],
  COUNT(*) AS Deaths,
  AVG(CAST([Age] AS FLOAT)) AS AvgAge
FROM dbo.FirefighterDeaths
GROUP BY [Cause_Of_Death]
ORDER BY AvgAge DESC;


-- Count of incidents with missing/invalid critical data (data quality check)
-- Purpose: Find records needing cleaning (missing dates, age, or cause).

SELECT
  SUM(CASE WHEN TRY_CONVERT(date,[Date_of_Incident]) IS NULL THEN 1 ELSE 0 END) AS MissingIncidentDate,
  SUM(CASE WHEN TRY_CONVERT(date,[Date_of_Death]) IS NULL THEN 1 ELSE 0 END) AS MissingDeathDate,
  SUM(CASE WHEN [Age] IS NULL OR LTRIM(RTRIM([Age])) = '' THEN 1 ELSE 0 END) AS MissingAge,
  SUM(CASE WHEN [Cause_Of_Death] IS NULL OR LTRIM(RTRIM([Cause_Of_Death])) = '' THEN 1 ELSE 0 END) AS MissingCause
FROM FirefighterDeaths;


-- Rolling 5-year average deaths (smoothing)
-- Purpose: Remove year-to-year noise and show trend.

WITH C AS (
  SELECT TRY_CONVERT(date, [Date_of_Incident]) AS IncidentDate FROM dbo.FirefighterDeaths
), Y AS (
  SELECT YEAR(IncidentDate) AS Year, COUNT(*) AS Deaths
  FROM C WHERE IncidentDate IS NOT NULL
  GROUP BY YEAR(IncidentDate)
)
SELECT
  Year,
  Deaths,
  ROUND(AVG(CAST(Deaths AS FLOAT)) OVER (ORDER BY Year ROWS BETWEEN 4 PRECEDING AND CURRENT ROW),2) AS Rolling5yrAvg
FROM Y
ORDER BY Year;