require 'spec_helper_acceptance'

describe 'postgresql::server::grant:', :unless => UNSUPPORTED_PLATFORMS.include?(fact('osfamily')) do

  db = 'grant_priv_test'
  owner = 'psql_grant_priv_owner'
  user = 'psql_grant_priv_tester'
  password = 'psql_grant_role_pw'

  pp_setup = <<-EOS.unindent
    $db = #{db}
    $owner = #{owner}
    $user = #{user}
    $password = #{password}

    class { 'postgresql::server': }

    postgresql::server::role { $owner:
      password_hash => postgresql_password($owner, $password),
    }

    # Since we are not testing pg_hba or any of that, make a local user for ident auth
    user { $owner:
      ensure => present,
    }

    postgresql::server::database { $db:
      owner   => $owner,
      require => Postgresql::Server::Role[$owner],
    }

    # Create a user to grant privileges to
    postgresql::server::role { $user:
      db      => $db,
      require => Postgresql::Server::Database[$db],
    }

    # Make a local user for ident auth
    user { $user:
      ensure => present,
    }

    # Grant them connect to the database
    postgresql::server::database_grant { "allow connect for ${user}":
      privilege => 'CONNECT',
      db        => $db,
      role      => $user,
    }
  EOS

  context 'sequence' do
    it 'should grant usage on a sequence to a user' do
      begin
        pp = pp_setup + <<-EOS.unindent

          postgresql_psql { 'create test sequence':
            command   => 'CREATE SEQUENCE test_seq',
            db        => $db,
            psql_user => $owner,
            unless    => "SELECT 1 FROM information_schema.sequences WHERE sequence_name = 'test_seq'",
            require   => Postgresql::Server::Database[$db],
          }

          postgresql::server::grant { 'grant usage on test_seq':
            privilege   => 'USAGE',
            object_type => 'SEQUENCE',
            object_name => 'test_seq',
            db          => $db,
            role        => $user,
            require     => [ Postgresql_psql['create test sequence'],
                             Postgresql::Server::Role[$user], ]
          }
        EOS

        apply_manifest(pp, :catch_failures => true)
        apply_manifest(pp, :catch_changes => true)

        ## Check that the privilege was granted to the user
        psql("-d #{db} --command=\"SELECT 1 WHERE has_sequence_privilege('#{user}', 'test_seq', 'USAGE')\"", user) do |r|
          expect(r.stdout).to match(/\(1 row\)/)
          expect(r.stderr).to eq('')
        end
      end
    end
  end

  context 'all sequences' do
    it 'should grant usage on all sequences to a user' do
      begin
        pp = pp_setup + <<-EOS.unindent

          postgresql_psql { 'create test sequences':
            command   => 'CREATE SEQUENCE test_seq2; CREATE SEQUENCE test_seq3;',
            db        => $db,
            psql_user => $owner,
            unless    => "SELECT 1 FROM information_schema.sequences WHERE sequence_name = 'test_seq2'",
            require   => Postgresql::Server::Database[$db],
          }

          postgresql::server::grant { 'grant usage on all sequences':
            privilege   => 'USAGE',
            object_type => 'ALL SEQUENCES IN SCHEMA',
            object_name => 'public',
            db          => $db,
            role        => $user,
            require     => [ Postgresql_psql['create test sequences'],
                             Postgresql::Server::Role[$user], ]
          }
        EOS

        apply_manifest(pp, :catch_failures => true)
        apply_manifest(pp, :catch_changes => true)

        ## Check that the privileges were granted to the user
        psql("-d #{db} --command=\"SELECT 1 WHERE has_sequence_privilege('#{user}', 'test_seq2', 'USAGE') AND has_sequence_privilege('#{user}', 'test_seq3', 'USAGE')\"", user) do |r|
          expect(r.stdout).to match(/\(1 row\)/)
          expect(r.stderr).to eq('')
        end
      end
    end
  end
end
