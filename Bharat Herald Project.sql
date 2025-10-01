-- 1.
SELECT *
FROM (
    SELECT 
        c.city AS city_name,
        DATE_FORMAT(STR_TO_DATE(ps.Date, '%d-%b-%y'), '%Y-%m') AS month,
        ps.Net_Circulation,
        (ps.Net_Circulation - LAG(ps.Net_Circulation) OVER (PARTITION BY ps.City_ID ORDER BY STR_TO_DATE(ps.Date, '%d-%b-%y'))) AS mo_m_change
    FROM print_sales ps
    JOIN dim__city c ON ps.City_ID = c.city_id
) AS sub
WHERE mo_m_change < 0
ORDER BY mo_m_change ASC
LIMIT 3;


-- 2.
SELECT *
FROM (
    SELECT 
        f.Year,
        c.standard_ad_category AS category_name,
        SUM(CAST(f.ad_revenue_in_inr AS DECIMAL(18,2))) AS category_revenue,
        SUM(SUM(CAST(f.ad_revenue_in_inr AS DECIMAL(18,2)))) 
            OVER (PARTITION BY f.Year) AS total_revenue_year,
        (SUM(CAST(f.ad_revenue_in_inr AS DECIMAL(18,2))) 
         / SUM(SUM(CAST(f.ad_revenue_in_inr AS DECIMAL(18,2)))) 
            OVER (PARTITION BY f.Year)) * 100 AS pct_of_year_total
    FROM fact_ad_rev f
    JOIN dim_category c ON f.ad_category = c.ad_category_id
    GROUP BY f.Year, c.standard_ad_category
) AS sub
ORDER BY Year, pct_of_year_total DESC;

-- 3.
SELECT *
FROM (
    SELECT 
        c.city AS city_name,
        SUM(ps.`Copies Sold`) AS copies_printed_2024,
        SUM(ps.Net_Circulation) AS net_circulation_2024,
        SUM(ps.Net_Circulation) / SUM(ps.`Copies Sold`) AS efficiency_ratio,
        RANK() OVER (ORDER BY SUM(ps.Net_Circulation) / SUM(ps.`Copies Sold`) DESC) AS efficiency_rank_2024
    FROM print_sales ps
    JOIN dim__city c ON ps.City_ID = c.city_id
    WHERE ps.Year = 2024
    GROUP BY c.city
) AS sub
WHERE efficiency_rank_2024 <= 5
ORDER BY efficiency_rank_2024;

-- 4.
SELECT 
    c.city AS city_name,
    MAX(CASE WHEN f.Quarter = 'Q1' THEN f.internet_penetration END) AS internet_rate_q1_2021,
    MAX(CASE WHEN f.Quarter = 'Q4' THEN f.internet_penetration END) AS internet_rate_q4_2021,
    (MAX(CASE WHEN f.Quarter = 'Q4' THEN f.internet_penetration END) -
     MAX(CASE WHEN f.Quarter = 'Q1' THEN f.internet_penetration END)) AS delta_internet_rate
FROM fact_city_read f
JOIN dim__city c ON f.city_id = c.city_id
WHERE f.Year = 2021
GROUP BY c.city
ORDER BY delta_internet_rate DESC;

-- 5.
WITH city_yearly AS (
    SELECT 
        nc.City_ID,
        c.city AS city_name,
        nc.Year,
        nc.yearly_net_circulation,
        ar.yearly_ad_revenue,
        LAG(nc.yearly_net_circulation) OVER (PARTITION BY nc.City_ID ORDER BY nc.Year) AS prev_net_circ,
        LAG(ar.yearly_ad_revenue) OVER (PARTITION BY nc.City_ID ORDER BY nc.Year) AS prev_ad_rev
    FROM
        (SELECT City_ID, Year, SUM(Net_Circulation) AS yearly_net_circulation
         FROM print_sales
         GROUP BY City_ID, Year) nc
    LEFT JOIN
        (SELECT df.City_ID, f.Year, SUM(CAST(f.ad_revenue_in_inr AS DECIMAL(18,2))) AS yearly_ad_revenue
         FROM fact_ad_rev f
         JOIN dim_fact_ad_rev df ON f.edition_id = df.edition_ID
         GROUP BY df.City_ID, f.Year) ar
    ON nc.City_ID = ar.City_ID AND nc.Year = ar.Year
    JOIN dim__city c ON nc.City_ID = c.city_id
    WHERE nc.Year BETWEEN 2019 AND 2024
)
SELECT 
    city_name,
    Year,
    yearly_net_circulation,
    yearly_ad_revenue,
    CASE WHEN prev_net_circ IS NULL OR yearly_net_circulation < prev_net_circ THEN 'Yes' ELSE 'No' END AS is_declining_print,
    CASE WHEN prev_ad_rev IS NULL OR yearly_ad_revenue < prev_ad_rev THEN 'Yes' ELSE 'No' END AS is_declining_ad_revenue,
    CASE WHEN 
        (prev_net_circ IS NULL OR yearly_net_circulation < prev_net_circ)
        AND (prev_ad_rev IS NULL OR yearly_ad_revenue < prev_ad_rev)
        THEN 'Yes' ELSE 'No' END AS is_declining_both
FROM city_yearly
ORDER BY Year;

-- 6. 
WITH city_scores AS (
    SELECT
        c.city AS city_name,
        (f.smartphone_penetration + f.internet_penetration + f.literacy_rate)/3 AS readiness_score_2021,
        f.digital_penetration AS engagement_metric_2021
    FROM fact_city_read f
    JOIN dim__city c ON f.city_id = c.city_id
    WHERE f.Year = 2021
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY city_name ORDER BY readiness_score_2021 DESC) AS rn,
           RANK() OVER (ORDER BY readiness_score_2021 DESC) AS readiness_rank_desc,
           RANK() OVER (ORDER BY engagement_metric_2021 ASC) AS engagement_rank_asc
    FROM city_scores
)
SELECT city_name,
       readiness_score_2021,
       engagement_metric_2021,
       readiness_rank_desc,
       engagement_rank_asc,
       CASE 
           WHEN readiness_rank_desc = 1 AND engagement_rank_asc <= 3 THEN 'Yes'
           ELSE 'No'
       END AS is_outlier
FROM ranked
WHERE rn = 1
ORDER BY readiness_rank_desc, engagement_rank_asc;
