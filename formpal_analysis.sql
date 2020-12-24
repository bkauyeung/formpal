 /* # 1. Which non-sandbox links have the most payments that are completed but not submitted in the last month?
# 2. What are the fids and unsubmitted count associated with those links? */

select
  links.id as linkid,
  links.fid,
  count(links.id) as number_completed
from links
inner join payments on links.id = payments.link_id
  where (sandbox = FALSE
    and paid_at is not null
    and submitted_at is null
    and (paid_at > now() - interval '1 month'))
group by linkid
order by number_completed desc
limit 10;

/* 2. For each week in the year with recorded payments, how many non-sandbox completed payments
don't have a submitted_at date? And what's the percentage for that week compared to total non-sandbox
completed payments? (there is a way to get week numbers from postgres and group by week). */

/* select week(cast(paid_at as date)) <- this doesnt give the actual week for some reason */

select
  date_part('week', cast(paid_at as date)) as week_number,
  count(*) as total,
  to_char(round(100.0*count(*)/
    (select count(*) from links inner join payments on links.id=payments.link_id
    where sandbox = FALSE and payments.paid_at is not null and submitted_at is null), 2), '999D99%') as "Percentage"
from links
inner join payments on links.id = payments.link_id
  where
    (sandbox = FALSE
    and payments.paid_at is not null
    and submitted_at is null)
group by week_number
order by week_number ASC;

/* # Gives you 353 total.
select count(*) from links inner join payments on links.id=payments.link_id
where sandbox = FALSE and payments.paid_at is not null and submitted_at is null; */

/*
# Using case when statements.
# Percentage for that week compared to total non-sandbox completed payments of that week.
select date_part('week', cast(paid_at as date)) as week_number, sum(case when paid_at
is not NULL and submitted_at is null then 1
else 0 END) as "Total",
sum(case when paid_at is not NULL and submitted_at is null then 1 else 0 END)/
sum(case when paid_at is not NULL and submitted_at is not null then 1 else 0 END) as "Percentage"
from links inner join payments on links.id = payments.link_id
where sandbox = FALSE
group by week_number
order by week_number ASC;
*/

3. Can you exclude from #2 all payments taken by a user *before* their first submitted payment?
This is because I think users often do one or two test payments through FP before the form goes live,
but they dont bother submitting their own form when they get the receipt code (this is much more, you
may have to chain multiple queries using subselects or WITH clauses).

# Test 1: Get all the payments where sandbox = FALSE and submitted_at is null.
select
  date_part('week', cast(paid_at as date)) as week_number,
  count(*) as total
from payments
inner join links on links.id=payments.link_id
  where (sandbox = FALSE
    and payments.paid_at is not null
    and submitted_at is NULL)
group by week_number
order by week_number ASC;

# Test 2: Get all the minimum submitted_at dates for test 1.
select link_id, min(submitted_at)
from payments
inner join links on links.id=payments.link_id
where (submitted_at is not null and sandbox = FALSE)
group by link_id;

# Answer #3: combine the minimum submitted_at dates with the payments dates.
with extra_table(link_id, earliest_submit) as (select link_id, min(submitted_at)
  from payments
  inner join links
    on links.id=payments.link_id
  where (submitted_at is not null and sandbox = FALSE) group by link_id)
select
  date_part('week', cast(paid_at as date)) as week_number,
  count(*) as total
from payments
  inner join links on links.id=payments.link_id
  inner join extra_table
  on payments.link_id=extra_table.link_id
    where (sandbox = FALSE and submitted_at is NULL
    and payments.paid_at > extra_table.earliest_submit)
group by week_number
order by week_number ASC;

# Test 4: Does week 51 really have 10 payments that are before the submitted date?
# This shows that there are 2 payments before the submitted date and if you toggle < to >
# you see that there are also 2 payments after the submitted date.

with extra_table(link_id, earliest_submit)
  as (select link_id, min(submitted_at)
  from payments inner join links on links.id=payments.link_id
    where (submitted_at is not null and sandbox = FALSE) group by link_id)
select
  date_part('week', cast(paid_at as date)) as week_number,
  payments.link_id, paid_at,
  earliest_submit
from payments
inner join links
  on links.id=payments.link_id
inner join extra_table
  on payments.link_id=extra_table.link_id
  where (sandbox = FALSE and submitted_at is NULL
    and payments.paid_at < extra_table.earliest_submit)
order by week_number DESC limit 15;

# Test 5 - changing answer 2 to see what is wrong with the numbers
# Answer 2 below showing 12 transactions in week 51
select
  date_part('week', cast(paid_at as date)) as week_number,
  paid_at, count(*) as total,
  to_char(round(100.0*count(*)/
    (select count(*) from links
    inner join payments on links.id=payments.link_id
      where sandbox = FALSE and payments.paid_at is not null and submitted_at is null), 2), '999D99%') as "Percentage"
from links
inner join payments on links.id = payments.link_id
  where (sandbox = FALSE and payments.paid_at is not null and submitted_at is null)
group by week_number, paid_at
order by week_number DESC;

# 3 Looking at the Answer - We get the number of people who made payments after the link submitted date.
with extra_table(link_id, earliest_submit) as
  (select link_id, min(submitted_at)
    from payments inner join links on links.id=payments.link_id
    where (submitted_at is not null and sandbox = FALSE) group by link_id)
select
  date_part('week', cast(paid_at as date)) as week_number,
  payments.link_id, paid_at, earliest_submit,
  count(*) as total
from links
inner join payments on links.id = payments.link_id left join extra_table on payments.link_id = extra_table.link_id
  where (sandbox = FALSE and payments.paid_at is not null and submitted_at is null)
group by week_number, paid_at, payments.link_id, earliest_submit
order by week_number DESC;

# Test 6 - Is the reason why there are so many blanks because some links with paid_at dates have no submitted_at dates at all?
select distinct link_id,
  date_part('week', cast(paid_at as date)) as week_number
from payments
order by week_number DESC;

select distinct link_id,
  submitted_at,
  date_part('week', cast(paid_at as date)) as week_number
from payments
where submitted_at is not null
order by week_number DESC;

select * from payments where link_id = '8YfItB4pUcm95z18'


-- 4. Histogram of how many days between signup and card added for users who added a card?

-- # works in bigquery/mysql
-- # select datediff('day', cast(created_at as date) - cast(card_added_at as date))
-- # as date_difference
-- # from users
-- # where created_at is not null and card_added_at is not null;

-- # Test 1 -> get the difference in days
select id, DATE_PART('day', card_added_at - created_at) as date_difference from users where created_at is not null and card_added_at is not null;

with histogram_table (floor_difference, ceiling_difference) as
  (select
    floor(DATE_PART('day', card_added_at - created_at)/5)*5 as floor_diff,
    floor(date_part('day', card_added_at - created_at)/5)*5 + 5 as ceiling_diff
    from users
    where created_at is not null
    and card_added_at is not null)
select
  concat(floor_difference, ' to ', ceiling_difference) as difference_in_days,
  count(*) as customer_count
from histogram_table
group by floor_difference, ceiling_difference
order by floor_difference;
