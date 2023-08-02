CREATE FUNCTION dbo.customweek(@date DATE)
RETURNS INT
AS
BEGIN
    RETURN DATEPART(WEEK, @date);
END;


-- First, drop the table if it already exists
IF OBJECT_ID('clean_weekly_sales', 'U') IS NOT NULL
    DROP TABLE clean_weekly_sales;

-- Create the clean_weekly_sales table
CREATE TABLE clean_weekly_sales
(
    week_date DATE,
    week_number INT,
    month_number INT,
    calendar_year INT,
    region VARCHAR(50),
    platform VARCHAR(50),
    segment VARCHAR(50),
    customer_type VARCHAR(50),
    age_band VARCHAR(50),
    demographic VARCHAR(50),
    transactions INT,
    sales NUMERIC(18, 2),
    avg_transaction NUMERIC(18, 2)
);

-- Insert data into the clean_weekly_sales table
INSERT INTO clean_weekly_sales
SELECT 
    CAST(weekdate AS DATE) AS week_date,
    dbo.custom_week(CAST(weekdate AS DATE)) AS week_number,
    DATEPART(MONTH, CAST(weekdate AS DATE)) AS month_number,
    DATEPART(YEAR, CAST(weekdate AS DATE)) AS calendar_year,
    region,
    platform,
    segment,
    customer_type,
    (
        CASE
            WHEN RIGHT(segment, 1) = '1' THEN 'Young Adults'
            WHEN RIGHT(segment, 1) = '2' THEN 'Middle Aged'
            WHEN RIGHT(segment, 1) IN ('3', '4') THEN 'Retirees'
            ELSE 'unknown'
        END
    ) AS age_band,
    (
        CASE
            WHEN LEFT(segment, 1) = 'C' THEN 'Couples'
            WHEN LEFT(segment, 1) = 'F' THEN 'Families'
            ELSE 'unknown'
        END
    ) AS demographic,
    transactions,
    sales,
    ROUND(sales * 1.0 / transactions, 2) AS avg_transaction
FROM case5_;

---What day of the week is used for each week_date value?
ALTER TABLE clean_weekly_sales
ADD dayname_ VARCHAR(20);

UPDATE clean_weekly_sales
SET dayname_ = DATENAME(weekday, week_date);

--How many total transactions were there for each year in the dataset?
SELECT SUM(transactions) total_transactions, calendar_year
FROM case5_
GROUP BY calendar_year
ORDER BY 1 

--What is the total sales for each region for each month?
SELECT 
    region,
    DATENAME(MONTH, DATEFROMPARTS(1900, month_number, 1)) AS month,
    SUM(sales) AS total_sales
FROM clean_weekly_sales
GROUP BY region, month_number
ORDER BY region, month_number;

--What is the total count of transactions for each platform?
---including commas in the output
SELECT 
    platform,
    FORMAT(SUM(transactions), 'N0') AS total_transactions
FROM clean_weekly_sales
GROUP BY platform;

--What is the percentage of sales for Retail vs Shopify for each month?
SELECT calendar_year, month_number,
  ROUND(100 * SUM(
    CASE
      WHEN platform = 'Retail' THEN sales
      ELSE 0
    END
  ) / SUM(sales), 2) AS retail_percentage,
  ROUND(100 * SUM(
    CASE
      WHEN platform = 'Shopify' THEN sales
      ELSE 0
    END
  ) / SUM(sales), 2) AS shopify_percentage
FROM clean_weekly_sales
GROUP BY calendar_year, month_number
ORDER BY calendar_year, month_number;

--What is the percentage of sales by demographic for each year in the dataset?
SELECT calendar_year,
  ROUND(100 * SUM(
    CASE
      WHEN demographic = 'Couples' THEN sales
    END
  ) / SUM(sales), 2) AS couples_sales,
  ROUND(100 * SUM(
    CASE
      WHEN demographic = 'Families' THEN sales
    END
  ) / SUM(sales), 2) AS families_sales,
  ROUND(100 * SUM(
    CASE
      WHEN demographic = 'unknown' THEN sales
    END
  ) / SUM(sales), 2) AS unknown_sales
FROM clean_weekly_sales
GROUP BY calendar_year
ORDER BY calendar_year;

--Which age_band and demographic values contribute the most to Retail sales?
WITH retail_total AS (
  SELECT * 
  FROM clean_weekly_sales
  WHERE platform = 'Retail'
)
SELECT age_band, demographic, SUM(sales) AS subtotal,
  ROUND(100 * SUM(sales) / 
  (SELECT SUM(sales) FROM retail_total), 2) AS percentage_contribution
FROM retail_total
GROUP BY age_band, demographic
ORDER BY subtotal DESC;

--Can we use the avg_transaction column to find the average transaction size for each year for Retail vs Shopify?
--If not — how would you calculate it instead?
SELECT calendar_year, platform, 
  ROUND(AVG(avg_transaction), 2) AS avg_transaction,
  ROUND(SUM(sales) / NULLIF(SUM(transactions), 0), 2) AS proper_avg_transactions
FROM clean_weekly_sales
GROUP BY calendar_year, platform 
ORDER BY calendar_year, platform;

--What is the total sales for the 4 weeks before and after 2020–06–15?
--— What is the growth or reduction rate in actual values and percentage of sales?
WITH four_weeks_before AS (
  SELECT DISTINCT week_date
  FROM clean_weekly_sales
  WHERE week_date BETWEEN DATEADD(WEEK, -4, '2020-06-15') AND DATEADD(WEEK, -1, '2020-06-15')
),
four_weeks_after AS (
  SELECT DISTINCT week_date
  FROM clean_weekly_sales
  WHERE week_date BETWEEN '2020-06-15' AND DATEADD(WEEK, 3, '2020-06-15')
),
summations AS (
  SELECT 
    fw.sales AS four_weeks_before_sales,
    fa.sales AS four_weeks_after_sales
  FROM (
    SELECT week_date, sales
    FROM clean_weekly_sales
    WHERE week_date IN (SELECT week_date FROM four_weeks_before)
  ) fw
  JOIN (
    SELECT week_date, sales
    FROM clean_weekly_sales
    WHERE week_date IN (SELECT week_date FROM four_weeks_after)
  ) fa ON fw.week_date = fa.week_date
)
SELECT 
  four_weeks_before_sales,
  four_weeks_after_sales,
  four_weeks_after_sales - four_weeks_before_sales AS variance,
  ROUND(
    100 * (four_weeks_after_sales - four_weeks_before_sales) * 1.0 / NULLIF(four_weeks_before_sales, 0), 2
  ) AS percentage_change
FROM summations;
