use setup;
run_tests;

__DATA__
=== ACCESS TEST 1
This tests the case where header is not set.
--- request
GET /
--- error_code : 200

=== ACCESS TEST 2
This test case test the scenario where head with invalid value.
--- more_headers
denied:2
--- request
GET /
--- error_code : 200

=== ACCESS TEST 3
This test case test with valid header and value.
--- more_headers
denied:1
--- request
GET /
--- response_body
Access denied
--- error_code : 401

=== ACCESS TEST 4
This test case test specific IP address is blocked. (here local 127.0.0.1)
--- request
GET /api/v1/core/
--- response_body
Access denied
--- error_code : 401

=== ACCESS TEST 5
This test case test specific merchant blocked based on header key
--- more_headers
cust:test
--- request
GET /
--- response_body
Access denied
--- error_code : 401

=== ACCESS TEST 6
This test case test that multiple merchant can be blocked.
--- more_headers
cust:test1
--- request
GET /
--- response_body
Access denied
--- error_code : 401

=== ACCESS TEST 7
Check if other customer can pass through
--- more_headers
cust:test2
--- request
GET /
--- error_code : 200

=== ACCESS TEST 8
This test case test that merchant is blocked using param key
--- request
GET /?account_id=1234
--- response_body
Access denied
--- error_code : 401

=== ACCESS TEST 9
This test case test that multiple merchant is blocked using same param key.
--- request
GET /?account_id=1235
--- response_body
Access denied
--- error_code : 401

=== ACCESS TEST 10
Check if other account_id pass through
--- request
GET /?account_id=1236
--- error_code : 200

