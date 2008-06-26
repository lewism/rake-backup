require 'backup'

backup_mysql :username => 'root', :to => '~/foo.gz'
duplicity :source => '/', :destination => 'scp://backup@backup-server/client-name', :includes => %w(+/root +/etc -/), :passphrase => 'foobar', :encrypt_key => 'encrypt' 