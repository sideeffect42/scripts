#!/usr/bin/env perl
# -*- mode: perl; indent-tabs-mode: nil -*-
#
# Script to migrate (open) issues from a GitLab project to a Redmine project.
#
# This scripts needs to be configured _first_ by modifying the source code
# (cf. CONFIGURE HERE below).
#
# As always, make a backup _before_ running this script!
#
# Requirements:
#   - Perl
#     - JSON
#     - LWP::UserAgent
#   - Pandoc for converting Markdown to Textile formatting (sub gfm2textile)

use warnings;
use strict;

use utf8;
use open ':utf8';       # all open() use UTF-8
use open ':std';        # standard filehandles too

use threads;
use Thread::Queue;

use JSON;               # required p5-json
use File::Basename;
use HTML::Entities;
use IPC::Open2;
use LWP::UserAgent;     # requires p5-libwww-perl p5-lwp-protocol-https
use URI::Escape;
# Uncomment these for debugging
# use LWP::ConsoleLogger::Easy qw( debug_ua );
# use Data::Dumper;

### CONFIGURE HERE

# GitLab (from)

my $GITLAB_HOST = 'https://gitlab.example.com';
my $GITLAB_API_PRIVATE_TOKEN = 'xqcQbTUIxcyF00TPKmWA';              # obtained from 'Profile -> Access Tokens'
my $GITLAB_USER = 'john';
my $GITLAB_PASSWD = 'password1234';

my $GITLAB_GROUP_NAME = 'mygroup';
my $GITLAB_REPO_NAME = 'myproject';
my $GITLAB_PROJECT_ID = 42;

# Redmine (to)

my $REDMINE_BASE = 'https://redmine.example.com';
my $REDMINE_AUTHOR = 'admin';
my $REDMINE_API_KEY = '02c1c6486b27927cbce36a1e6f766e880ec980aa';   # REST API must be enabled in 'Administration -> Settings -> API'; then key can be obtained from 'My account -> API access key'
my $REDMINE_PROJECT_NAME = 'myproject';

my %REDMINE_STATUS_MAP = ('opened' => 'New', 'closed' => 'Closed');
my %REDMINE_USER_MAP = ();

### STOP CONFIGURING HERE


my $GITLAB_BASE = "${GITLAB_HOST}/api/v4";
# my $GITLAB_PROJECT_ID = uri_escape_utf8 "${GITLAB_GROUP_NAME}/${GITLAB_REPO_NAME}";
my $GITLAB_PROJECT_BASE = "${GITLAB_HOST}/${GITLAB_GROUP_NAME}/${GITLAB_REPO_NAME}";

my $gitlab_user_agent = LWP::UserAgent->new;
$gitlab_user_agent->cookie_jar({});  # empty, temporary cookie jar
$gitlab_user_agent->default_header('Private-Token' => $GITLAB_API_PRIVATE_TOKEN);
my $redmine_user_agent = LWP::UserAgent->new;
$redmine_user_agent->default_header('X-Redmine-API-Key' => $REDMINE_API_KEY);

sub transfer_file_r2r {
    my ($ua1, $source_url, $ua2, $destination_url) = @_;

    # check for redirects
    my $head = $ua1->head($source_url);
    die $head->status_line unless $head->is_success;

    # my $real_src = ($head->header('Location') || $source_url);
    my $real_src = $source_url;

    my $_old_ua1_show_process = $ua1->show_progress;
    $ua1->show_progress(0);
    my $_old_ua2_show_process = $ua2->show_progress;
    $ua2->show_progress(0);

    my $q :shared = Thread::Queue->new;

    my $thr_ul = threads->create(
        sub {
            my $filesize = $q->dequeue;

            print "Content-Length: ${filesize}\n";

            my $req = HTTP::Request->new('POST' => $destination_url);
            $req->content_type('application/octet-stream');
            $req->header('Content-Length' => $filesize);
            $req->content(sub {
                my $chunk = $q->dequeue(1);

                if (defined $chunk) {
                    print "send ".length($chunk)." bytes\n";
                    return $chunk;
                } else {
                    return '';
                }
            });

            my $resp = $ua2->request($req);

            die "Upload to ${destination_url} failed" unless $resp->is_success;
            return $resp;
        });
    my $thr_dl = threads->create(
        sub {
            # Request metadata (filesize required for upload to work, MIME type
            # required to attach to Redmine).

            my $head_req = HTTP::Request->new(
                'HEAD' => $real_src,
                [
                    'Private-Token' => $GITLAB_API_PRIVATE_TOKEN,
                ]);
            my $head = $ua1->request($head_req);

            my $filesize = $head->header("Content-Length");
            print "Content-Length: ${filesize}\n";
            my $filetype = $head->header("Content-Type");

            # send file size over to the upload thread
            $q->enqueue($filesize);

            my $req = HTTP::Request->new('GET' => $real_src);
            my $resp = $ua1->request($req, sub {
                my ($chunk, $response, $proto) = @_;
                print "recv ".length($chunk)." bytes\n";
                $q->enqueue($chunk);
            });

            $q->end();
            die "Download of ${source_url} failed" unless $resp->is_success;

            return ($filetype, $filesize);
        });

    my ($filetype, $filesize) = $thr_dl->join();
    my $upload_resp = $thr_ul->join();

    printf "Transfer complete.\n";

    $ua1->show_progress($_old_ua1_show_process);
    $ua2->show_progress($_old_ua2_show_process);

    my $json = decode_json($upload_resp->content);

    return ($filetype, $filesize, $json->{'upload'}{'token'});
}

sub gfm2textile {
    my $mdtext = shift;

    my $pid = open2 my $reader, my $writer, 'pandoc', '-p', '-f', 'gfm', '-t', 'textile';
    binmode $writer, ':encoding(UTF-8)';
    binmode $reader, ':encoding(UTF-8)';
    print $writer "${mdtext}\n";
    close $writer;
    my $textiletext = do { local $/; <$reader> };
    waitpid $pid, 0;

    # post processing

    # fix strikethrough
    $textiletext =~ s:<s>(.*?)</s>:-$1-:g;

    # remove label for stupid "$" links
    $textiletext =~ s/"\$":(\S+)/$1/g;

    # fix list check boxes
    # $textiletext =~ s:^(\s*\*\s*)\[ \]:$1&#x2610;:g;
    # $textiletext =~ s:^(\s*\*\s*)\[x\]:$1&#x2611;:g;

    # remove HTML entities in URLs, attachments, inline images
    # $textiletext =~ s/"(.*?)":(\S+)/"\"$1\"".decode_entities($2)/eg;
    # $textiletext =~ s/attachment:"(.*?)"/"attachment:\"".decode_entities($2)."\""/eg;
    # $textiletext =~ s/attachment:(\S+)/"attachment:".decode_entities($2)/eg;

    return decode_entities $textiletext;
}

sub migrate_attachment {
    my $upload_path = shift;
    my $upload_prefix = dirname $upload_path;
    my $upload_file = basename $upload_path;
    my $upload_file_enc = uri_escape_utf8 $upload_file;
    my $upload_path_enc = $upload_prefix.'/'.$upload_file_enc;
    my $src_url = $GITLAB_PROJECT_BASE.$upload_path_enc;

    print "Migrating ${upload_path_enc} to Redmine.\n";

    # NOTE: Streaming transfer does not work because GitLab does not send a Content-Length header for attachments while Redmine requires it.
    # my ($filetype, $filesize, $redmine_token) = transfer_file_r2r(
    #     $gitlab_user_agent => $src_url,
    #     $redmine_user_agent => "${REDMINE_BASE}/uploads.json?filename=${filename}");

    my $resp_down = $gitlab_user_agent->get($src_url);
    die "Download of ${src_url} failed: ".$resp_down->status_line unless $resp_down->is_success;

    # my $filename = $resp_down->filename;
    my $filename = $upload_file;
    my $filename_enc = uri_escape_utf8 $filename;
    my $filetype = $resp_down->header('Content-Type');
    my $filesize = length $resp_down->content;

    print "Received ${filename} (${filesize} bytes).\n";

    my $dst_url = "${REDMINE_BASE}/uploads.json?filename=${filename_enc}";
    my $req_up = HTTP::Request->new('POST' => $dst_url);
    $req_up->content_type('application/octet-stream');
    $req_up->content($resp_down->content);
    my $resp_up = $redmine_user_agent->request($req_up);

    die "Upload to ${dst_url} failed: ".$resp_up->status_line unless $resp_up->is_success;

    print "Upload complete.\n";

    my $json = decode_json($resp_up->content);
    my $redmine_token = $json->{'upload'}{'token'};

    my $mimetype = (defined $filetype ? $filetype : 'application/octet-stream');

    return {
        'token' => $redmine_token,
        'filename' => $filename,
        'content_type' => $mimetype
    };
}

sub proc_body {
    my ($body, $ticket_id_map) = @_;
    my @uploads;

    # Transfer attachments over to Redmine
    # NOTE: This is done prior to converting the markup to Textile because
    # pandoc converts combining characters which GitLab does not like when we 
    # try to request the file.
    local *replace_url = sub {
        my ($flag, $title, $upload_url) = @_;
        my $upload = migrate_attachment $upload_url;

        push @uploads, $upload;

        if ($flag eq '!') {
            # embedded images will be converted correctly by Pandoc
            return sprintf " !%s(%s)! ", $upload->{filename}, $title;
        } else {
            # other attachment links won't work, so we output Textile already
            # (Pandoc will leave it alone because it doesn't look like GFM)
            return ' attachment:'.$upload->{filename}.' ';
        }
    };
    # \s* for misspelled links in Markdown…
    $body =~ s:(!?)\[(.*?)\]\s*\((/uploads/[0-9a-f]+/.*?)\):replace_url($1, $2, $3):eg;

    my $textile = gfm2textile $body;

    # Map GitLab ticket IDs (at least references to older ones :-/)
    local *update_ticket_id = sub {
        my $gl_id = shift;

        my $redmine_id = $ticket_id_map->{$2};
        return $redmine_id if $redmine_id;
        # else return a link to GitLab
        return "\"${GITLAB_REPO_NAME}#${gl_id}\":${GITLAB_PROJECT_BASE}/-/issues/${gl_id} ";
    };
    $textile =~ s/(\s)\#([0-9]+)/$1.update_ticket_id($2)/eg;

    # Make Git commit: links
    $textile =~ s/(\s)([0-9a-f]{40})/$1commit:$2/gi;

    return ($textile, \@uploads);
}

sub gitlab_login {
    my ($username, $password, $ua, $base_url) = @_;

    my $login_page = $ua->get("${base_url}/users/sign_in");
    my $csrf_token = $1 if $login_page->content =~ /<meta name="csrf-token" content="([^"]*)"/;

    # do login
    my $login_resp = $ua->post("${base_url}/users/sign_in" , {
        'user[login]' => $username,
        'user[password]' => $password,
        'authenticity_token' => $csrf_token
        });
    die 'login failed: '.$login_resp->status_line unless $login_resp->code == 302;
    print "Logged in to ${base_url} as: ${username}\n";
}

sub gitlab_logout {
    my ($ua, $base_url) = @_;

    $ua->post("${base_url}/users/sign_out");
    print "Logged out from ${base_url}.\n";
}

sub gitlab_api_request {
    my ($method, $endpoint, $headers, $content) = @_;
    my $fullurl = $GITLAB_BASE.$endpoint;
    my $request = HTTP::Request->new($method => $fullurl, $headers, $content);
    my $response = $gitlab_user_agent->request($request);
    die "Request failed: ${method} ${fullurl}: $response->status_line" unless $response->is_success;
    return $response;
}

sub gitlab_get_all_issues {
    my ($project_id, $state) = @_;
    $state = "all" unless defined $state;

    my $page = 1;
    my $total_pages = 0;
    my @issues = ();
    do {
        print "Fetching page ${page}".($total_pages?" (of ${total_pages})":"")."\n";
        my $response = gitlab_api_request('GET' => "/projects/${GITLAB_PROJECT_ID}/issues?state=${state}&order_by=created_at&sort=asc&page=${page}");#"&iids[]=1");
        $total_pages = int($response->header("X-Total-Pages"));
        push(@issues, @{decode_json($response->decoded_content)});
    } while ($page++ < $total_pages);

    my @sorted = sort { $a->{'iid'} <=> $b->{'iid'} } @issues;
    return \@sorted;
}

sub redmine_request {
    my ($method, $endpoint, $headers, $content) = @_;
    my $fullurl = $REDMINE_BASE.$endpoint;
    my $request = HTTP::Request->new($method, $fullurl, $headers, $content);
    my $response = $redmine_user_agent->request($request);
    die "Request failed: ${method} ${fullurl}: ".$response->status_line."\n".$response->content unless $response->is_success;
    return $response;
}

sub redmine_get_project_by_name {
    my ($project_name) = @_;
    # FIXME: support more than 100 projects
    my $response = redmine_request('GET' => '/projects.json?limit=100');
    my $projects = decode_json($response->content)->{'projects'};
    my @match_projects = grep { $_->{'identifier'} eq $project_name } @$projects;
    die "Cannot find project: ${project_name}" unless scalar @match_projects;
    return $match_projects[0];
}

sub redmine_whoami {
    my $response = redmine_request('GET' => '/users/current.json');
    my $user = decode_json($response->content);
    return $user->{'user'};
}

sub redmine_get_user_by_name {
    my ($user_name) = @_;
    my $response = redmine_request('GET' => "/users.json?name=${user_name}");
    my $res = decode_json($response->content);
    die "No match for user name: ${user_name}" if $res->{'total_count'} < 1;
    die "Multiple matches for user name: ${user_name}" if $res->{'total_count'} > 1;
    return $res->{'users'}->[0];
}

sub redmine_get_status_id_by_name {
    my ($status_name) = @_;
    my $response = redmine_request('GET' => '/issue_statuses.json');
    my $statuses = decode_json($response->content)->{'issue_statuses'};
    my @match_statuses = grep { $_->{'name'} eq $status_name} @$statuses;
    die "Cannot find Redmine status: ${status_name}" unless scalar @match_statuses;
    return $match_statuses[0];
}


# Log in to GitLab.
gitlab_login $GITLAB_USER, $GITLAB_PASSWD, $gitlab_user_agent, $GITLAB_HOST;

# Log in to Redmine.
my $redmine_me = redmine_whoami()->{'login'};
print "Logged in to ${REDMINE_BASE} as: ${redmine_me}\n";

# Determine Redmine project ID
my $REDMINE_PROJECT_ID = (redmine_get_project_by_name $REDMINE_PROJECT_NAME)->{'id'};
print "Resolved Redmine project '${REDMINE_PROJECT_NAME}' to ID ${REDMINE_PROJECT_ID}\n";

# getting issues from GitLab
print "GitLab project ID: ${GITLAB_PROJECT_ID}\n";
my $issues = gitlab_get_all_issues($GITLAB_PROJECT_ID);

# processing them
my %redmine_status_id_map;
while ((my $gitlab_status, my $redmine_status) = each (%REDMINE_STATUS_MAP)) {
    $redmine_status_id_map{$gitlab_status} = redmine_get_status_id_by_name($redmine_status)->{'id'};
}

my %ticket_id_map;

foreach my $issue (@$issues) {
    eval {
        print "Migrating GitLab issue #$issue->{iid} to Redmine\n";

        my ($textiletext, $uploads) = proc_body $issue->{description}, \%ticket_id_map;

        my $description = "_Imported from ${GITLAB_HOST}: \"${GITLAB_REPO_NAME}#$issue->{iid}\":$issue->{web_url}_\n\n";
        $description .= $textiletext."\n\n";

        if (scalar(@{$issue->{labels}})) {
            $description .= "\$labels: ".join(', ', @{$issue->{labels}})."\$\n"
        }
        $description .= "\$created_at: ".$issue->{created_at}."\$\n";
        $description .= "\$updated_at: ".$issue->{updated_at}."\$\n";
        $description .= "\$author: ".$issue->{author}{username}."\$\n";

        my %redmine_issue;
        $redmine_issue{issue}{uploads} = $uploads;
        $redmine_issue{issue}{project_id} = $REDMINE_PROJECT_ID;
        $redmine_issue{issue}{status_id} = $redmine_status_id_map{'opened'};
        $redmine_issue{issue}{subject} = $issue->{title};
        $redmine_issue{issue}{is_private} = ($issue->{confidential} ? JSON::true : JSON::false);
        $redmine_issue{issue}{'start_date'} = substr $issue->{'created_at'}, 0, 10;
        if ($issue->{'due_date'}) {
            $redmine_issue{issue}{'due_date'} = substr $issue->{'due_date'}, 0, 10;
        }
        if (defined $issue->{'assignee'}{'username'}) {
            $description .= "\$assignee: ".$issue->{'assignee'}{'username'}."\$\n";

            eval {
                my $assignee = lc $issue->{'assignee'}{'username'};
                my $redmine_user_id = redmine_get_user_by_name $assignee->{'id'};
                $redmine_issue{issue}{assigned_to_id} = $redmine_user_id;
            };
        }
        chomp $description;
        $redmine_issue{issue}{description} = $description;

        # creating basic issue in Redmine
        my $switch_user = $redmine_me;
        eval {
            my $ticket_author = lc $issue->{author}{username};
            my $redmine_user = $REDMINE_USER_MAP{$ticket_author} || $ticket_author;
            $switch_user = redmine_get_user_by_name($redmine_user)->{'login'};
        };

        # print Dumper %redmine_issue;

        my $response = redmine_request(
            'POST' => '/issues.json',
            [
                'Content-Type' => 'application/json; charset=UTF-8',
                'X-Redmine-Switch-User' => $switch_user
            ],
            encode_json(\%redmine_issue));
        my $redmine_issue_id = decode_json($response->content)->{'issue'}{'id'};
        $ticket_id_map{$issue->{iid}} = $redmine_issue_id;

        print "Created Redmine issue #${redmine_issue_id} (as ${switch_user})\n";

        # fetching notes if existing
        if (0 < $issue->{user_notes_count}) {
            print "Found $issue->{user_notes_count} notes\n";

            my $response = gitlab_api_request(
                'GET' => "/projects/${GITLAB_PROJECT_ID}/issues/$issue->{iid}/notes?order_by=created_at&sort=asc");
            my @notes = @{decode_json($response->decoded_content)};
            foreach my $note (@notes) {
                # system notes (like "changed the description") are of little interest and therefore skipped
                next if $note->{system};

                eval {
                    print "Adding GitLab note $note->{id} (as ${switch_user})\n";

                    # store note in Redmine
                    my ($textiletext, $new_uploads) = proc_body $note->{body}, \%ticket_id_map;

                    my %redmine_note;
                    if (@$new_uploads > 0) {
                        push @$uploads, @$new_uploads;
                        $redmine_note{issue}{uploads} = $new_uploads;
                    }
                    if ($issue->{'confidential'}) {
                        $redmine_note{issue}{private_notes} = JSON::true;
                    }

                    my $notes = $textiletext."\n\n";
                    $notes .= "\$created_at: ".$note->{created_at}."\$\n";
                    $notes .= "\$author: ".$note->{author}{username}."\$\n";
                    chomp $notes;
                    $redmine_note{issue}{notes} = $notes;

                    my $switch_user = $redmine_me;
                    eval {
                        my $note_author = lc $note->{'author'}{'username'};
                        my $redmine_user = $REDMINE_USER_MAP{$note_author} || $note_author;
                        $switch_user = redmine_get_user_by_name($redmine_user)->{'login'};
                    };

                    # print Dumper %redmine_note;

                    my $rm_notes_response = redmine_request(
                        'PUT' => "/issues/${redmine_issue_id}.json",
                        [
                            'Content-Type' => 'application/json; charset=UTF-8',
                            'X-Redmine-Switch-User' => $switch_user
                        ],
                        encode_json(\%redmine_note));
                };
                print STDERR "Adding note failed: ".$@ if $@;
            }
        }

        if ($issue->{'state'} eq 'closed') {
            eval {
                my $switch_user = $redmine_me;

                my %close_obj;
                $close_obj{'issue'}{'status_id'} = $redmine_status_id_map{'closed'};
                $close_obj{'issue'}{'notes'} = "\$closed_at: ".$issue->{'closed_at'}."\$\n";

                if (defined $issue->{'closed_by'}{'username'}) {
                    $close_obj{'issue'}{'notes'} .= "\$closed_by: ".$issue->{'closed_by'}{'username'}."\$\n";

                    eval {
                        my $close_user = lc $issue->{'closed_by'}{'username'};
                        my $redmine_user = $REDMINE_USER_MAP{$close_user} || $close_user;
                        $switch_user = redmine_get_user_by_name($redmine_user)->{'login'};
                    };
                }

                redmine_request(
                    'PUT' => "/issues/${redmine_issue_id}.json",
                    [
                        'Content-Type' => 'application/json; charset=UTF-8',
                        'X-Redmine-Switch-User' => $switch_user
                    ],
                    encode_json(\%close_obj));

                print "Closed ticket (as ${switch_user}).\n";
            };
            print STDERR "Could not close issue: ".$@ if $@;
        }
    };
    print STDERR "Skipping issue because of error: ".$@ if $@;
}

gitlab_logout $gitlab_user_agent, $GITLAB_HOST;

exit 0;
