use setup;
no_shuffle;
run_tests;

__DATA__


=== RATELIMIT HEADER TEST 1 (for header merchant:test1)
Wait till start of next minute (init)
try requests till threshold value (for header merchant=test)
--- init
(my $sec,my $min) = localtime;
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime;
}while( $min == $original_min );
--- more_headers
merchant:test1
--- pipelined_requests eval
["GET /api/v1/core/", "GET /api/v1/core/", "GET /api/v1/core/"]
--- response_body eval
["ok\n", "ok\n", "ok\n"]

=== RATELIMIT HEADER TEST 2 (for header merchant:test1)
request post threshold value at header level, expected to hit threshold error
--- more_headers
merchant:test1
--- request
GET /api/v1/core/
--- response_body
Request threshold reached, please try again later
--- error_code : 429

=== RATELIMIT HEADER TEST 3
request post threshold value for a different header value, expected to go through (for header merchant=test2)
--- more_headers
merchant:test2
--- request
GET /api/v1/core/
--- response_body
ok

=== RATELIMIT HEADER TEST 4 (for header merchant:test1)
Wait till start of next minute (init)
try new request for rate limited header value (for header merchant=test1), should work now
--- init
(my $sec,my $min) = localtime;
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime;
}while( $min == $original_min );
--- more_headers
merchant:test1
--- request
GET /api/v1/core/
--- response_body
ok

=== RATELIMIT HEADER TEST 5 (for overridden header merchant:test)
Wait till start of next minute (init)
try requests till threshold value (for header merchant=test)
--- init
(my $sec,my $min) = localtime;
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime;
}while( $min == $original_min );
--- more_headers
merchant:test
--- pipelined_requests eval
["GET /api/v1/core/", "GET /api/v1/core/", "GET /api/v1/core/", "GET /api/v1/core/", "GET /api/v1/core/"]
--- response_body eval
["ok\n", "ok\n", "ok\n", "ok\n", "ok\n"]

=== RATELIMIT HEADER TEST 6 (for overridden header merchant:test)
request post threshold value at header level, expected to hit threshold error (for header merchant=test)
--- more_headers
merchant:test
--- request
GET /api/v1/core/
--- response_body
Request threshold reached, please try again later
--- error_code : 429

=== RATELIMIT HEADER TEST 7
request post threshold value for a different header value, expected to go through (for header merchant=test2)
--- more_headers
merchant:test2
--- request
GET /api/v1/core/
--- response_body
ok

=== RATELIMIT HEADER TEST 8
Wait till start of next minute (init)
try new request for rate limited header value (for header merchant=test), should work now
--- init
(my $sec,my $min) = localtime;
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime;
}while( $min == $original_min );
--- more_headers
merchant:test
--- request
GET /api/v1/core/
--- response_body
ok

