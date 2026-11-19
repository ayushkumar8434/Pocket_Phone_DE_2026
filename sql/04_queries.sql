-- =====================================================================
-- Pocket Phone AP 2026 — Marketplace Query Collection
-- File: sql/04_queries.sql
-- Version: 1.0
-- Description: 50 MySQL/MariaDB examples for marketplace retrieval,
--              reporting, business workflows, and data modification.
--
-- Schema assumptions: table and column names follow the 12-table schema
-- supplied with this query request. Foreign keys connect the *_id columns.
-- Status examples used below (such as 'available', 'paid', 'delivered')
-- should match the values enforced by the deployed schema.
-- =====================================================================

-- ===================== SECTION 1: BASIC RETRIEVAL QUERIES =====================

-- Query 1: Retrieve users with their city, state, and country.
-- Use case: Display user profiles with their registered location.
SELECT
    u.user_id,
    u.username,
    u.email,
    u.phone_number,
    c.city_name AS city,
    s.state_name AS state,
    s.country AS country
FROM `Users` AS u
LEFT JOIN `Cities` AS c ON c.city_id = u.city_id
LEFT JOIN `States` AS s ON s.state_id = c.state_id
WHERE u.user_id = 1001;

-- Query 2: List all phone brands alphabetically.
-- Use case: Populate brand selectors and catalog pages.
SELECT
    b.brand_id,
    b.brand_name,
    b.brand_logo,
    b.description,
    b.country_of_origin AS origin_country
FROM `Brands` AS b
ORDER BY b.brand_name ASC;

-- Query 3: List phone models with their brand names and core specifications.
-- Use case: Browse the catalog by release year and brand.
SELECT
    pm.model_id,
    b.brand_name,
    pm.model_name,
    pm.release_year,
    pm.display_size,
    pm.processor,
    pm.os_version,
    pm.battery_capacity
FROM `Phone_Models` AS pm
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
WHERE pm.release_year >= 2022
ORDER BY pm.release_year DESC, b.brand_name, pm.model_name;

-- Query 4: Show available listings with seller, model, brand, and current price.
-- Use case: Render the marketplace inventory; current-price lookup is indexed.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pl.storage_capacity,
    pl.ram,
    pl.color,
    pl.condition AS phone_condition,
    pl.listing_date,
    u.username AS seller_name,
    pr.base_price,
    pr.discount_amount,
    pr.final_price
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
JOIN `Users` AS u ON u.user_id = pl.seller_id
LEFT JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pl.status = 'available'
ORDER BY pl.listing_date DESC, pl.listing_id DESC;

-- Query 5: Retrieve camera specifications by phone model.
-- Use case: Show camera details on a model comparison page.
SELECT
    b.brand_name,
    pm.model_name,
    cs.camera_type,
    cs.megapixels,
    cs.aperture
FROM `Camera_Specs` AS cs
JOIN `Phone_Models` AS pm ON pm.model_id = cs.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
WHERE pm.model_id = 501
ORDER BY cs.megapixels DESC, cs.camera_type;

-- ===================== SECTION 2: FILTERING AND SEARCH QUERIES =====================

-- Query 6: Search available listings from a selected brand.
-- Use case: Brand-filtered catalog results.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pl.storage_capacity,
    pl.ram,
    pl.color,
    pr.final_price
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE b.brand_name = 'Samsung'
  AND pl.status = 'available'
ORDER BY pr.final_price ASC, pl.listing_id;

-- Query 7: Find available phones within an inclusive price range.
-- Use case: Price-filtered search; BETWEEN includes both endpoints.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pl.storage_capacity,
    pr.final_price AS current_price
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pr.final_price BETWEEN 15000.00 AND 40000.00
  AND pl.status = 'available'
ORDER BY pr.final_price ASC;

-- Query 8: Find models whose names contain a search phrase.
-- Use case: User-entered model-name search; bind the pattern as a parameter.
SELECT
    pm.model_id,
    b.brand_name,
    pm.model_name,
    pm.release_year
FROM `Phone_Models` AS pm
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
WHERE pm.model_name LIKE '%Galaxy%'
ORDER BY b.brand_name, pm.model_name;

-- Query 9: Return only verified, currently available listings.
-- Use case: Prioritize listings that have passed marketplace verification.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pl.is_verified,
    pl.verification_date,
    pr.final_price
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
LEFT JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pl.is_verified = 1
  AND pl.verification_date IS NOT NULL
  AND pl.status = 'available'
ORDER BY pl.verification_date DESC;

-- Query 10: Find listings in selected cosmetic conditions.
-- Use case: Filter inventory to conditions commonly selected by buyers.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pl.condition AS phone_condition,
    pl.color,
    pr.final_price
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
LEFT JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pl.condition IN ('new', 'like_new', 'good')
  AND pl.status = 'available'
ORDER BY FIELD(pl.condition, 'new', 'like_new', 'good'), pr.final_price;

-- ===================== SECTION 3: AGGREGATE FUNCTIONS =====================

-- Query 11: Count all listings per brand, including brands with zero listings.
-- Use case: Catalog coverage and inventory reporting.
SELECT
    b.brand_id,
    b.brand_name,
    COUNT(pl.listing_id) AS total_listings
FROM `Brands` AS b
LEFT JOIN `Phone_Models` AS pm ON pm.brand_id = b.brand_id
LEFT JOIN `Phone_Listings` AS pl ON pl.model_id = pm.model_id
GROUP BY b.brand_id, b.brand_name
ORDER BY total_listings DESC, b.brand_name;

-- Query 12: Summarize current listing prices by brand.
-- Use case: Compare brand price bands; NULL prices are excluded from the aggregates.
SELECT
    b.brand_name,
    COALESCE(ROUND(AVG(pr.final_price), 2), 0.00) AS average_price,
    COALESCE(MIN(pr.final_price), 0.00) AS minimum_price,
    COALESCE(MAX(pr.final_price), 0.00) AS maximum_price
FROM `Brands` AS b
LEFT JOIN `Phone_Models` AS pm ON pm.brand_id = b.brand_id
LEFT JOIN `Phone_Listings` AS pl ON pl.model_id = pm.model_id AND pl.status = 'available'
LEFT JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
GROUP BY b.brand_id, b.brand_name
ORDER BY average_price DESC, b.brand_name;

-- Query 13: Sum successful transaction amounts for each seller.
-- Use case: Seller revenue reporting; COALESCE returns zero for sellers without sales.
SELECT
    u.user_id AS seller_id,
    u.username AS seller_name,
    COALESCE(SUM(t.amount), 0.00) AS total_revenue
FROM `Users` AS u
LEFT JOIN `Phone_Listings` AS pl ON pl.seller_id = u.user_id
LEFT JOIN `Transactions` AS t
    ON t.listing_id = pl.listing_id
   AND t.payment_status = 'paid'
GROUP BY u.user_id, u.username
ORDER BY total_revenue DESC, u.user_id;

-- Query 14: Calculate average rating and review count for every listing.
-- Use case: Listing quality summaries; unrated listings remain visible.
SELECT
    pl.listing_id,
    COALESCE(ROUND(AVG(r.rating), 2), 0.00) AS average_rating,
    COUNT(r.review_id) AS review_count
FROM `Phone_Listings` AS pl
LEFT JOIN `Reviews` AS r ON r.listing_id = pl.listing_id
GROUP BY pl.listing_id
ORDER BY average_rating DESC, review_count DESC, pl.listing_id;

-- Query 15: Count users by city and state, retaining locations with zero users.
-- Use case: Geographic registration reporting.
SELECT
    s.state_name,
    c.city_name,
    COUNT(u.user_id) AS user_count
FROM `States` AS s
LEFT JOIN `Cities` AS c ON c.state_id = s.state_id
LEFT JOIN `Users` AS u ON u.city_id = c.city_id
GROUP BY s.state_id, s.state_name, c.city_id, c.city_name
ORDER BY s.state_name, c.city_name;

-- ===================== SECTION 4: JOIN QUERIES =====================

-- Query 16: Show completed/paid transactions with buyer and seller details.
-- Use case: Support staff transaction lookup and order administration.
SELECT
    t.transaction_id,
    t.transaction_date,
    t.amount,
    t.payment_method,
    t.payment_status,
    buyer.username AS buyer_name,
    buyer.email AS buyer_email,
    seller.username AS seller_name,
    pl.listing_id
FROM `Transactions` AS t
JOIN `Users` AS buyer ON buyer.user_id = t.buyer_id
JOIN `Phone_Listings` AS pl ON pl.listing_id = t.listing_id
JOIN `Users` AS seller ON seller.user_id = pl.seller_id
WHERE t.payment_status = 'paid'
ORDER BY t.transaction_date DESC;

-- Query 17: List all phone models, whether or not they have any listing.
-- Use case: Identify models missing marketplace inventory.
SELECT
    pm.model_id,
    b.brand_name,
    pm.model_name,
    COUNT(pl.listing_id) AS listing_count
FROM `Phone_Models` AS pm
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
LEFT JOIN `Phone_Listings` AS pl ON pl.model_id = pm.model_id
GROUP BY pm.model_id, b.brand_name, pm.model_name
ORDER BY listing_count ASC, b.brand_name, pm.model_name;

-- Query 18: Show each user and their wishlist size, including empty wishlists.
-- Use case: Account overview; COUNT ignores the NULL placeholder row.
SELECT
    u.user_id,
    u.username,
    COUNT(w.wishlist_id) AS wishlist_count
FROM `Users` AS u
LEFT JOIN `Wishlist` AS w ON w.user_id = u.user_id
GROUP BY u.user_id, u.username
ORDER BY wishlist_count DESC, u.user_id;

-- Query 19: Retrieve transaction, buyer, seller, phone, and shipping details.
-- Use case: Fulfillment dashboard; LEFT JOIN preserves orders without shipping rows.
SELECT
    t.transaction_id,
    t.transaction_date,
    t.amount,
    t.order_status,
    buyer.username AS buyer_name,
    seller.username AS seller_name,
    b.brand_name,
    pm.model_name,
    sd.shipping_status,
    sd.tracking_number,
    sd.shipped_date,
    sd.delivered_date
FROM `Transactions` AS t
JOIN `Users` AS buyer ON buyer.user_id = t.buyer_id
JOIN `Phone_Listings` AS pl ON pl.listing_id = t.listing_id
JOIN `Users` AS seller ON seller.user_id = pl.seller_id
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
LEFT JOIN `Shipping_Details` AS sd ON sd.transaction_id = t.transaction_id
ORDER BY t.transaction_date DESC;

-- Query 20: Find pairs of different users registered in the same city.
-- Use case: Analyze local marketplace communities; user IDs prevent duplicate pairs.
SELECT
    u1.city_id,
    u1.user_id AS first_user_id,
    u1.username AS first_username,
    u2.user_id AS second_user_id,
    u2.username AS second_username
FROM `Users` AS u1
JOIN `Users` AS u2
    ON u2.city_id = u1.city_id
   AND u2.user_id > u1.user_id
WHERE u1.city_id IS NOT NULL
ORDER BY u1.city_id, u1.user_id, u2.user_id;

-- ===================== SECTION 5: SUBQUERIES =====================

-- Query 21: Find available listings priced above the overall average current price.
-- Use case: Surface premium listings using a scalar subquery in WHERE.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pr.final_price
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pl.status = 'available'
  AND pr.final_price > (
      SELECT AVG(pr2.final_price)
      FROM `Pricing` AS pr2
      JOIN `Phone_Listings` AS pl2 ON pl2.listing_id = pr2.listing_id
      WHERE pr2.is_current = 1 AND pl2.status = 'available'
  )
ORDER BY pr.final_price DESC;

-- Query 22: Find sellers with more than five total listings.
-- Use case: Identify high-volume sellers; HAVING filters grouped seller counts.
SELECT
    u.user_id AS seller_id,
    u.username AS seller_name,
    (SELECT COUNT(*)
     FROM `Phone_Listings` AS pl2
     WHERE pl2.seller_id = u.user_id) AS listing_count
FROM `Users` AS u
WHERE (SELECT COUNT(*)
       FROM `Phone_Listings` AS pl3
       WHERE pl3.seller_id = u.user_id) > 5
ORDER BY listing_count DESC, u.user_id;

-- Query 23: Find the most expensive current listing for each brand.
-- Use case: Brand-level premium inventory using a correlated maximum subquery.
SELECT
    b.brand_name,
    pm.model_name,
    pl.listing_id,
    pr.final_price
FROM `Brands` AS b
JOIN `Phone_Models` AS pm ON pm.brand_id = b.brand_id
JOIN `Phone_Listings` AS pl ON pl.model_id = pm.model_id AND pl.status = 'available'
JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pr.final_price = (
    SELECT MAX(pr2.final_price)
    FROM `Phone_Models` AS pm2
    JOIN `Phone_Listings` AS pl2 ON pl2.model_id = pm2.model_id AND pl2.status = 'available'
    JOIN `Pricing` AS pr2 ON pr2.listing_id = pl2.listing_id AND pr2.is_current = 1
    WHERE pm2.brand_id = b.brand_id
)
ORDER BY b.brand_name, pl.listing_id;

-- Query 24: Find users who have both bought and sold at least one phone.
-- Use case: Identify marketplace participants using two correlated EXISTS checks.
SELECT
    u.user_id,
    u.username,
    u.email
FROM `Users` AS u
WHERE EXISTS (
    SELECT 1
    FROM `Transactions` AS t
    WHERE t.buyer_id = u.user_id
)
AND EXISTS (
    SELECT 1
    FROM `Phone_Listings` AS pl
    JOIN `Transactions` AS t2 ON t2.listing_id = pl.listing_id
    WHERE pl.seller_id = u.user_id
)
ORDER BY u.user_id;

-- Query 25: Find available listings that have never received a review.
-- Use case: Locate listings that may need buyer feedback.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pl.listing_date
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
WHERE pl.status = 'available'
  AND NOT EXISTS (
      SELECT 1
      FROM `Reviews` AS r
      WHERE r.listing_id = pl.listing_id
  )
ORDER BY pl.listing_date DESC;

-- ===================== SECTION 6: ADVANCED QUERIES =====================

-- Query 26: Rank the ten most popular models by wishlist additions.
-- Use case: Popularity report; HAVING suppresses models with no wishlist activity.
SELECT
    pm.model_id,
    b.brand_name,
    pm.model_name,
    COUNT(w.wishlist_id) AS wishlist_additions,
    COUNT(DISTINCT pl.listing_id) AS listing_count
FROM `Phone_Models` AS pm
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
LEFT JOIN `Phone_Listings` AS pl ON pl.model_id = pm.model_id
LEFT JOIN `Wishlist` AS w ON w.listing_id = pl.listing_id
GROUP BY pm.model_id, b.brand_name, pm.model_name
HAVING COUNT(w.wishlist_id) > 0
ORDER BY wishlist_additions DESC, listing_count DESC, pm.model_id
LIMIT 10;

-- Query 27: Summarize transactions by calendar month for the last 12 months.
-- Use case: Monthly order volume and revenue trend; date range is index-friendly.
SELECT
    DATE_FORMAT(t.transaction_date, '%Y-%m') AS transaction_month,
    COUNT(*) AS transaction_count,
    COALESCE(SUM(CASE WHEN t.payment_status = 'paid' THEN t.amount ELSE 0 END), 0.00)
        AS paid_revenue,
    COALESCE(AVG(t.amount), 0.00) AS average_order_amount
FROM `Transactions` AS t
WHERE t.transaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
GROUP BY DATE_FORMAT(t.transaction_date, '%Y-%m')
ORDER BY transaction_month DESC;

-- Query 28: Show best-rated listings with at least three reviews.
-- Use case: Recommendations based on meaningful review volume.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    ROUND(AVG(r.rating), 2) AS average_rating,
    COUNT(r.review_id) AS review_count
FROM `Phone_Listings` AS pl
JOIN `Reviews` AS r ON r.listing_id = pl.listing_id
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
GROUP BY pl.listing_id, b.brand_name, pm.model_name
HAVING COUNT(r.review_id) >= 3
ORDER BY average_rating DESC, review_count DESC, pl.listing_id
LIMIT 20;

-- Query 29: Compare seller performance using listings, completed sales, and revenue.
-- Use case: Seller operations dashboard; a paid transaction is treated as a sale.
SELECT
    u.user_id AS seller_id,
    u.username AS seller_name,
    COUNT(DISTINCT pl.listing_id) AS total_listings,
    COALESCE(sales.paid_sales, 0) AS paid_sales,
    COALESCE(sales.paid_revenue, 0.00) AS paid_revenue,
    COALESCE(ratings.average_listing_rating, 0.00) AS average_listing_rating
FROM `Users` AS u
LEFT JOIN `Phone_Listings` AS pl ON pl.seller_id = u.user_id
LEFT JOIN (
    SELECT
        pl2.seller_id,
        COUNT(DISTINCT t.transaction_id) AS paid_sales,
        SUM(t.amount) AS paid_revenue
    FROM `Phone_Listings` AS pl2
    JOIN `Transactions` AS t ON t.listing_id = pl2.listing_id
    WHERE t.payment_status = 'paid'
    GROUP BY pl2.seller_id
) AS sales ON sales.seller_id = u.user_id
LEFT JOIN (
    SELECT
        pl3.seller_id,
        AVG(r.rating) AS average_listing_rating
    FROM `Phone_Listings` AS pl3
    JOIN `Reviews` AS r ON r.listing_id = pl3.listing_id
    GROUP BY pl3.seller_id
) AS ratings ON ratings.seller_id = u.user_id
GROUP BY u.user_id, u.username, sales.paid_sales, sales.paid_revenue,
         ratings.average_listing_rating
ORDER BY paid_revenue DESC, paid_sales DESC, u.user_id;

-- Query 30: Summarize current prices by storage capacity.
-- Use case: Compare prices across storage tiers for available phones.
SELECT
    pl.storage_capacity,
    COUNT(pl.listing_id) AS available_listing_count,
    COALESCE(ROUND(AVG(pr.final_price), 2), 0.00) AS average_price,
    COALESCE(MIN(pr.final_price), 0.00) AS minimum_price,
    COALESCE(MAX(pr.final_price), 0.00) AS maximum_price
FROM `Phone_Listings` AS pl
LEFT JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pl.status = 'available'
GROUP BY pl.storage_capacity
ORDER BY pl.storage_capacity;

-- ===================== SECTION 7: DATA MODIFICATION QUERIES =====================

-- Query 31: Insert a new user account.
-- Use only after validating consent and uniqueness; hash the password in the app.
-- Bind every value using a prepared statement; never store a plaintext password.
INSERT INTO `Users` (
    username, email, password, phone_number, street_address,
    city_id, pincode, registration_date
)
VALUES (
    ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP
);

-- Query 32: Create a new phone listing for an existing model and seller.
-- Use after validating seller ownership, model ID, and allowed condition/status values.
INSERT INTO `Phone_Listings` (
    model_id, seller_id, storage_capacity, ram, color, `condition`,
    listing_date, status, is_verified, verification_date, listing_type
)
VALUES (
    ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, 'available', 0, NULL, 'standard'
);

-- Query 33: Add the initial price for a newly created listing.
-- Use within the same transaction as Query 32; enforce one current price per listing.
INSERT INTO `Pricing` (
    listing_id, base_price, discount_amount, final_price,
    price_updated_date, is_current
)
VALUES (
    ?, ?, ?, ?, CURRENT_TIMESTAMP, 1
);

-- Query 34: Mark a listing sold after its purchase is confirmed.
-- Use in the same transaction that records the successful order/payment.
UPDATE `Phone_Listings`
SET status = 'sold'
WHERE listing_id = ?
  AND status = 'available';

-- Query 35: Update editable user contact and location information.
-- Use only after verifying the authenticated user may edit this account.
UPDATE `Users`
SET phone_number = ?,
    street_address = ?,
    city_id = ?,
    pincode = ?
WHERE user_id = ?;

-- Query 36: Change payment status after receiving a trusted payment-provider event.
-- Use an idempotency key/provider reference in the application transaction flow.
UPDATE `Transactions`
SET payment_status = 'paid'
WHERE transaction_id = ?
  AND payment_status IN ('pending', 'processing');

-- Query 37: Update shipping progress after confirmation from the carrier.
-- Use only for the shipping record associated with the verified transaction.
UPDATE `Shipping_Details`
SET shipping_status = ?,
    tracking_number = COALESCE(?, tracking_number),
    shipped_date = COALESCE(shipped_date, CURRENT_TIMESTAMP)
WHERE shipping_id = ?;

-- Query 38: Soft deletion is not representable in the supplied Users schema.
-- Add an is_active BOOLEAN NOT NULL DEFAULT TRUE column before using this update.
-- After that migration, deactivate instead of physically deleting the account.
UPDATE `Users`
SET is_active = 0
WHERE user_id = ?
  AND is_active = 1;

-- Query 39: Withdraw a listing without deleting its transaction/review history.
-- Use when a seller cancels or removes an unsold item from the marketplace.
UPDATE `Phone_Listings`
SET status = 'removed'
WHERE listing_id = ?
  AND seller_id = ?
  AND status = 'available';

-- Query 40: Purge old, superseded pricing rows only after retention/archive checks.
-- Run in a maintenance window; never delete the current price or recent audit data.
DELETE FROM `Pricing`
WHERE is_current = 0
  AND price_updated_date < DATE_SUB(CURRENT_DATE(), INTERVAL 2 YEAR);

-- ===================== SECTION 8: BUSINESS-SPECIFIC QUERIES =====================

-- Query 41: Get today's featured drops.
-- Use case: Populate the daily Drops feed; half-open date range handles timestamps.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pl.color,
    pl.storage_capacity,
    pr.final_price
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
LEFT JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pl.listing_type = 'todays_drop'
  AND pl.listing_date >= CURRENT_DATE()
  AND pl.listing_date < CURRENT_DATE() + INTERVAL 1 DAY
  AND pl.status = 'available'
ORDER BY pl.listing_date DESC;

-- Query 42: Rank available phones by wishlist interest and completed purchases.
-- Use case: Popular Phones feed. View counts are unavailable because no view
-- tracking column/table exists in the supplied schema; wishlist and sales are proxies.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    COUNT(DISTINCT w.wishlist_id) AS wishlist_count,
    COUNT(DISTINCT CASE WHEN t.payment_status = 'paid' THEN t.transaction_id END)
        AS paid_purchase_count,
    COALESCE(pr.final_price, 0.00) AS current_price
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
LEFT JOIN `Wishlist` AS w ON w.listing_id = pl.listing_id
LEFT JOIN `Transactions` AS t ON t.listing_id = pl.listing_id
LEFT JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pl.status = 'available'
GROUP BY pl.listing_id, b.brand_name, pm.model_name, pr.final_price
ORDER BY wishlist_count DESC, paid_purchase_count DESC, pl.listing_id
LIMIT 20;

-- Query 43: Find discounted listings with a discount of at least 20 percent.
-- Use case: Good Deals feed; guard against NULL and zero base prices.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pr.base_price,
    pr.discount_amount,
    pr.final_price,
    ROUND(100.0 * pr.discount_amount / NULLIF(pr.base_price, 0), 2) AS discount_percent
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pl.status = 'available'
  AND pr.base_price > 0
  AND pr.discount_amount / pr.base_price >= 0.20
ORDER BY discount_percent DESC, pr.final_price ASC;

-- Query 44: Retrieve one buyer's purchase history and shipping state.
-- Use case: Account order-history page; replace the example ID with a bound parameter.
SELECT
    t.transaction_id,
    t.transaction_date,
    t.amount,
    t.payment_status,
    t.order_status,
    b.brand_name,
    pm.model_name,
    pl.storage_capacity,
    seller.username AS seller_name,
    sd.shipping_status,
    sd.tracking_number
FROM `Transactions` AS t
JOIN `Phone_Listings` AS pl ON pl.listing_id = t.listing_id
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
JOIN `Users` AS seller ON seller.user_id = pl.seller_id
LEFT JOIN `Shipping_Details` AS sd ON sd.transaction_id = t.transaction_id
WHERE t.buyer_id = 1001
ORDER BY t.transaction_date DESC;

-- Query 45: Retrieve a seller's listing and sales history.
-- Use case: Seller dashboard, including unsold listings and missing sale records.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pl.listing_date,
    pl.status AS listing_status,
    pr.final_price AS current_price,
    t.transaction_id,
    t.transaction_date,
    t.payment_status,
    t.amount AS sale_amount
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
LEFT JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
LEFT JOIN `Transactions` AS t ON t.listing_id = pl.listing_id
WHERE pl.seller_id = 2001
ORDER BY pl.listing_date DESC, t.transaction_date DESC;

-- Query 46: Show a user's wishlisted phones and each listing's current price.
-- Use case: Render the saved-items page, including listings lacking a price.
SELECT
    w.wishlist_id,
    w.added_date,
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pl.status AS listing_status,
    pr.final_price AS current_price
FROM `Wishlist` AS w
JOIN `Phone_Listings` AS pl ON pl.listing_id = w.listing_id
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
LEFT JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE w.user_id = 1001
ORDER BY w.added_date DESC;

-- Query 47: Search inventory with brand, price, condition, and storage filters.
-- Use case: Advanced search; replace sample criteria with prepared parameters.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    pl.`condition` AS phone_condition,
    pl.storage_capacity,
    pl.ram,
    pl.color,
    pr.final_price
FROM `Phone_Listings` AS pl
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pl.status = 'available'
  AND b.brand_name = 'Apple'
  AND pr.final_price BETWEEN 20000.00 AND 80000.00
    AND pl.`condition` IN ('like_new', 'good')
  AND pl.storage_capacity >= 128
ORDER BY pr.final_price ASC, pl.listing_date DESC;

-- Query 48: Estimate a phone's market value from similar available listings.
-- Use case: Seller pricing guidance based on same model, storage, and condition.
SELECT
    target.model_id,
    target.storage_capacity,
    target.`condition` AS phone_condition,
    COUNT(similar.listing_id) AS comparable_listing_count,
    COALESCE(ROUND(AVG(price.final_price), 2), 0.00) AS estimated_market_price,
    COALESCE(MIN(price.final_price), 0.00) AS comparable_minimum_price,
    COALESCE(MAX(price.final_price), 0.00) AS comparable_maximum_price
FROM `Phone_Listings` AS target
LEFT JOIN `Phone_Listings` AS similar
    ON similar.model_id = target.model_id
   AND similar.storage_capacity = target.storage_capacity
    AND similar.`condition` = target.`condition`
   AND similar.status = 'available'
   AND similar.listing_id <> target.listing_id
LEFT JOIN `Pricing` AS price
    ON price.listing_id = similar.listing_id
   AND price.is_current = 1
WHERE target.listing_id = 3001
GROUP BY target.model_id, target.storage_capacity, target.`condition`;

-- Query 49: Find available listings in a selected city or state.
-- Use case: Local marketplace discovery using the seller's registered city.
SELECT
    pl.listing_id,
    b.brand_name,
    pm.model_name,
    c.city_name,
    s.state_name,
    seller.pincode,
    pr.final_price
FROM `Phone_Listings` AS pl
JOIN `Users` AS seller ON seller.user_id = pl.seller_id
JOIN `Cities` AS c ON c.city_id = seller.city_id
JOIN `States` AS s ON s.state_id = c.state_id
JOIN `Phone_Models` AS pm ON pm.model_id = pl.model_id
JOIN `Brands` AS b ON b.brand_id = pm.brand_id
LEFT JOIN `Pricing` AS pr ON pr.listing_id = pl.listing_id AND pr.is_current = 1
WHERE pl.status = 'available'
  AND (c.city_name = 'Bengaluru' OR s.state_name = 'Karnataka')
ORDER BY c.city_name, pr.final_price ASC;

-- ===================== SECTION 9: ANALYTICS / DASHBOARD QUERY =====================

-- Query 50: Return core marketplace totals in one row using scalar aggregates.
-- Use case: Admin dashboard summary; separate scalar subqueries avoid join fan-out.
SELECT
    (SELECT COUNT(*) FROM `Users`) AS total_users,
    (SELECT COUNT(*) FROM `Phone_Listings`) AS total_listings,
    (SELECT COUNT(*) FROM `Phone_Listings` AS pl WHERE pl.status = 'available')
        AS available_listings,
    (SELECT COUNT(*) FROM `Transactions`) AS total_transactions,
    (SELECT COALESCE(SUM(t.amount), 0.00)
     FROM `Transactions` AS t
     WHERE t.payment_status = 'paid') AS paid_revenue,
    (SELECT COUNT(*) FROM `Reviews`) AS total_reviews,
    (SELECT COALESCE(ROUND(AVG(r.rating), 2), 0.00) FROM `Reviews` AS r)
        AS average_review_rating,
    (SELECT COUNT(*) FROM `Wishlist`) AS total_wishlist_entries,
    (SELECT COUNT(*) FROM `Phone_Listings` AS pl WHERE pl.is_verified = 1)
        AS verified_listings;

-- ===================== PERFORMANCE TIPS AND BEST PRACTICES =====================
-- 1. Add indexes for common joins/filters, e.g. Phone_Listings(model_id, status),
--    Phone_Listings(seller_id, status), Pricing(listing_id, is_current),
--    Transactions(buyer_id, transaction_date), Transactions(listing_id, payment_status),
--    Reviews(listing_id), Wishlist(user_id, listing_id), and Users(city_id).
-- 2. Use EXPLAIN (and EXPLAIN ANALYZE where supported) with representative data;
--    confirm index use and compare actual row counts before adding indexes.
-- 3. Avoid wrapping indexed timestamp columns in DATE() in WHERE predicates;
--    use half-open ranges as shown in Query 41 to keep predicates sargable.
-- 4. Keep current-price and listing-status values consistent with application rules;
--    consider enforcing a single current Pricing row per listing transactionally.
-- 5. Use transactions for multi-step checkout/listing changes and validate affected
--    row counts so concurrent updates cannot silently sell or withdraw stale listings.
-- 6. Bind all external values with prepared statements to prevent SQL injection;
--    never concatenate user input into SQL text. Hash passwords using a secure
--    password-hashing algorithm in the application before insertion.
-- 7. The supplied schema has no view-event data or user active/deactivated field.
--    Add a view-events table for true view-based popularity and an is_active column
--    before relying on those capabilities; Query 42 uses measurable proxies instead.
-- =====================================================================
