#!/usr/bin/perl

use strict;
use warnings;
use HTTP::Request::Common;
use LWP::UserAgent;
use Term::ReadKey;
use File::HomeDir;
use JSON::MaybeXS qw(encode_json decode_json);
use POSIX qw(strftime);
use Data::Serializer;
my $controller = Data::Serializer->new(
    digester => 'MD5',
    cipher   => 'DES',
    secret   => 'spittinsuperhotfire',
    compress => 1,
);

my $HOME = File::HomeDir->my_home;

my $PKG_NAME    = "Prime";
my $PKG_VER     = "1.2";
my $PKG_CONFIG  = "$HOME/.primeconf";
my $PKG_HELP    = <<HELP;

  $PKG_NAME ($PKG_VER) is a simple pastebin.com interface!
    Simply provide it with a list of files 
    and it'll take care of the rest (sort of).
  
  Example:
    prime file1.txt file2.js file3.log 

  Tips:
    Prime doesn't use the filename for uploading.
    If you want the paste to have a specific title,
    add "title:" to the first line of your file.
    The title line is not shown in the uploaded paste.
    Example:
      title: useful links
      + https://github.com/kyoto-shift/prime
      + https://pastebin.com
HELP

my ($API_KEY, $API_UNAME, $API_PASS, $API_USER_KEY);
my $API_URL       = 'https://pastebin.com/api/api_post.php';
my $API_LOGIN_URL = 'https://pastebin.com/api/api_login.php';

my ($CUR_DATE, $PASTE_TITLE);

my @file_lines;

sub start {
    if (!-e $PKG_CONFIG) {

        # if config doesn't exist, get info from user
        &initialize;
    }
    else {
        # if config exists, deserialize the file and assign to variables
        my $config_reference = $controller->retrieve("$PKG_CONFIG");
        $API_KEY      = $config_reference->{api_key};
        $API_USER_KEY = $config_reference->{api_user_key};
        $API_UNAME    = $config_reference->{api_uname};
        $API_PASS     = $config_reference->{api_pass};
        &proc_flags;
    }
    return;
}

sub initialize {
    print("It's your first time using $PKG_NAME!\n");
    print("Please input your Pastebin credentials to get started.\n");
    print(
        "Note: You will need a Pastebin API key. (https://pastebin.com/api#1)\n\n"
    );

    print("Pastebin API Key (Required): ");
    chomp($API_KEY = <>);
    if ($API_KEY eq "") {
        die("Error: A pastebin API key is required! Please try again.\n");
    }

    print("Pastebin Username (Leave blank for guest): ");
    chomp($API_UNAME = <>);

    print("Pastebin Password (Leave blank for guest): ");
    ReadMode('noecho');
    chomp($API_PASS = ReadLine(0));
    print("\n");

    ReadMode('normal');
    &check_login;
    $controller->store(
        {
            api_key      => $API_KEY,
            api_uname    => $API_UNAME,
            api_pass     => $API_PASS,
            api_user_key => $API_USER_KEY,
        },
        $PKG_CONFIG
    );
    print("Status: Credentials saved! Please restart $PKG_NAME.\n");
    return;
}

sub check_login {
    if (!$API_UNAME) {
        return;
    }
    my $login_info = {
        api_dev_key       => $API_KEY,
        api_user_name     => $API_UNAME,
        api_user_password => $API_PASS,
    };
    my $ua  = LWP::UserAgent->new();
    my $req = HTTP::Request::Common::POST($API_LOGIN_URL, $login_info);
    my $res = $ua->request($req);

    if ($res->is_success) {
        $API_USER_KEY = $res->content;
    }
    else {
        die("Error: Could not login! Please check login credentials.\n");
    }
    return;
}

sub proc_flags {
    my @flags     = @ARGV;
    my $cur_file  = 1;
    my $num_files = scalar(@flags);
    if (scalar(@flags) == 0 || $ARGV[0] =~ /(--help|-h)/x) {
        die($PKG_HELP, "\n");
    }

    foreach my $file (@flags) {
        print("Status: Uploading file $cur_file of $num_files\n");

        $CUR_DATE = strftime "%Y%m%d-%s", localtime;
        $PASTE_TITLE = '' || $CUR_DATE;

        &check_for_title($file);
        &upload_paste(@file_lines);

        undef(@file_lines);
        $cur_file++;
    }
    return;
}

sub check_for_title {
    open(my $handler, '<', $_[0])
      or die("Error: Could not open file '$_[0]'!\n");
    while (<$handler>) {
        push(@file_lines, $_);
    }
    close($handler);
    if ($file_lines[0] =~ /^title\:/x) {
        ($PASTE_TITLE) = $file_lines[0] =~ /\:(.*)/x;
        $PASTE_TITLE =~ s/^\s+//gx;
        shift(@file_lines);
    }
    return;
}

sub upload_paste {
    my $paste_data;

    if ($_[0] =~ /^\s$/x) {
        shift(@_);
    }

    $paste_data = [
        api_dev_key       => $API_KEY,
        api_user_name     => $API_UNAME,
        api_user_password => $API_PASS,
        api_user_key      => $API_USER_KEY,
        api_option        => "paste",
        api_paste_name    => $PASTE_TITLE,
        api_paste_code    => join("", @_),
    ];

    my $agent    = LWP::UserAgent->new();
    my $request  = HTTP::Request::Common::POST($API_URL, $paste_data);
    my $response = $agent->request($request);

    if ($response->is_success) {
        print("Status: Paste '$PASTE_TITLE' uploaded successfully!\n");
        print("URL: ", $response->content, "\n");
    }
    else {
        die("Error: ", $response->status_line, "\n");
    }

    sleep(1);
    return;
}

&start;
