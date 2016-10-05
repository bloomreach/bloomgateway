use setup;
no_shuffle;
run_tests;

__DATA__
=== RATELIMIT API TEST 1
Wait till start of next minute (init)
try requests till threshold value
--- init
(my $sec,my $min) = localtime;
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime();
}while( $min == $original_min );
--- pipelined_requests eval
["GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /"]
--- response_body eval
["ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n"]

=== RATELIMIT API TEST 2
request post threshold value at api level, expected to hit threshold error
--- request
GET /
--- response_body
Request threshold reached, please try again later
--- error_code : 429

=== RATELIMIT API TEST 3
Wait till start of next minute (init)
try new request, should work now
--- init
(my $sec,my $min) = localtime();
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime();
}while( $min == $original_min );
--- request
GET /
--- response_body
ok

