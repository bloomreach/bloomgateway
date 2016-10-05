use setup;
no_shuffle;
run_tests;

__DATA__
=== RATELIMIT PARAM TEST 1
Wait till start of next minute (init)
try requests till threshold value (for account 101)
--- init
(my $sec,my $min) = localtime;
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime;
}while( $min == $original_min );
--- pipelined_requests eval
["GET /?account_id=101", "GET /?account_id=101", "GET /?account_id=101", "GET /?account_id=101", "GET /?account_id=101", "GET /?account_id=101", "GET /?account_id=101"]
--- response_body eval
["ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n"]

=== RATELIMIT PARAM TEST 2
request post threshold value at api level, expected to hit threshold error (for account 101)
--- request
GET /?account_id=101
--- response_body
Request threshold reached, please try again later
--- error_code : 429

=== RATELIMIT PARAM TEST 3
The request should go through (for another account 102)
--- request
GET /?account_id=102
--- response_body
ok

=== RATELIMIT PARAM TEST 4
Wait till start of next minute (init)
try new request for rate limited param value, should work now (for account 101)
--- init
(my $sec,my $min) = localtime;
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime;
}while( $min == $original_min );
--- request
GET /?account_id=101
--- response_body
ok

=== RATELIMIT PARAM TEST 5 (FOR OVERRIDDEN ACCOUNT 1057)
Even though default threshold is 6 for an account, the account 1057 has overridden the default value to 8
After that the account 1057 should hit threshold error
waiting for new minute so that we don't hit minute level threshold for api "/"
--- init
(my $sec,my $min) = localtime;
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime;
}while( $min == $original_min );
--- pipelined_requests eval
["GET /api/v1/core/?account_id=1057", "GET /api/v1/core/?account_id=1057", "GET /api/v1/core/?account_id=1057", "GET /api/v1/core/?account_id=1057", "GET /api/v1/core/?account_id=1057", "GET /api/v1/core/?account_id=1057", "GET /api/v1/core/?account_id=1057", "GET /api/v1/core/?account_id=1057"]
--- response_body eval
["ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n"]

=== RATELIMIT PARAM TEST 6 (FOR OVERRIDDEN ACCOUNT 1057)
request post threshold value at param level, expected to hit threshold error (for account 1057)
--- request
GET /api/v1/core/?account_id=1057
--- response_body
Request threshold reached, please try again later
--- error_code : 429


=== RATELIMIT PARAM TEST 7 (FOR OVERRIDDEN ACCOUNT 1057)
The request should go through after minute is changed
--- init
(my $sec,my $min) = localtime;
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime;
}while( $min == $original_min );
--- request
GET /api/v1/core/?account_id=1057
--- response_body
ok
