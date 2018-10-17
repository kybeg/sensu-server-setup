# VARIABLES

$RABBITMQ_PASSWD = "398hhgaihdliauhe893"

$ADMIN_PASSWD = "sensuadminpass"

$SENSU_VERSION = "1.4"

$SENSU_CONFIG = "
{
      \"rabbitmq\": {
        \"ssl\": {
          \"private_key_file\": \"/etc/sensu/ssl/client_key.pem\",
          \"cert_chain_file\": \"/etc/sensu/ssl/client_cert.pem\"
        },
        \"port\": 5671,
        \"host\": \"localhost\",
        \"user\": \"sensu\",
        \"password\": \"$RABBITMQ_PASSWD\",
        \"vhost\": \"/sensu\"
      },
      \"redis\": {
        \"host\": \"localhost\",
        \"port\": 6379
      },
      \"api\": {
        \"host\": \"localhost\",
        \"port\": 4567
      },
      \"dashboard\": {
        \"host\": \"localhost\",
        \"port\": 8080,
        \"user\": \"admin\",
        \"password\": \"$ADMIN_PASSWD\"
      },
      \"handlers\" : {
        \"default\": {
          \"type\": \"pipe\",
          \"command\": \"/bin/true\"
        }
      }
    }
"


$SENSU_CLIENT_CONFIG = "
{
\"client\":{
\"name\":\"$hostname\",
\"address\":\"$ipaddress\",
\"subscriptions\":[\"test\"]
}
}
"

$UCHIWA_CONFIG = "{
  \"sensu\": [
    {
      \"name\": \"Site 1\",
      \"host\": \"localhost\",
      \"port\": 4567,
      \"timeout\": 5
    }
  ],
  \"uchiwa\": {
    \"host\": \"0.0.0.0\",
    \"port\": 3000,
    \"interval\": 5
  }
}"

# SSL certificates

exec { "download-key-script" :
    path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
    command => "wget http://docs.sensu.io/sensu-core/1.4/files/sensu_ssl_tool.tar && tar -xvf sensu_ssl_tool.tar -C /tmp",
    unless => "ls /tmp/sensu_ssl_tool",
}

exec { "create-keys" :
    path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
    command => "/tmp/sensu_ssl_tool/ssl_certs.sh generate",
    cwd => "/tmp/sensu_ssl_tool",
    require => Exec['download-key-script'],
    unless => "ls client && ls server",
    }


# RABBIT

package { "erlang-nox" :
   ensure => "present",
}

file { "/etc/apt/sources.list.d/rabbitmq.list" :
    ensure => present,
    content => "deb     http://www.rabbitmq.com/debian/ testing main",
    require => Package['erlang-nox']
    }



exec { "install-rabbit-repo-key" :
    path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
    command => "curl https://www.rabbitmq.com/rabbitmq-release-signing-key.asc | apt-key add -; apt-get update",
    require => File["/etc/apt/sources.list.d/rabbitmq.list"],
    unless => "apt-key list | grep 'RabbitMQ Release Signing Key'",
    }

package { "rabbitmq-server" :
    ensure => latest,
    require => Exec["install-rabbit-repo-key"],
}

service { "rabbitmq-server" :
    ensure => running,
    require => Package['rabbitmq-server'],
    }

file { "/etc/rabbitmq/ssl" :
  ensure => directory,
  require => Package['rabbitmq-server'],
}

exec { "copy-keys" :
     path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
     command => "cp /tmp/sensu_ssl_tool/server/cert.pem /etc/rabbitmq/ssl; cp /tmp/sensu_ssl_tool/server/key.pem /etc/rabbitmq/ssl; cp /tmp/sensu_ssl_tool/sensu_ca/cacert.pem /etc/rabbitmq/ssl",
     unless => "ls /etc/rabbitmq/ssl/cacert.pem",
     require => File['/etc/rabbitmq/ssl'],
}

$RABBITMQ_CONFIG = '
[
  {rabbit, [
     {ssl_listeners, [5671]},
     {ssl_options, [{cacertfile,"/etc/rabbitmq/ssl/cacert.pem"},
                    {certfile,"/etc/rabbitmq/ssl/cert.pem"},
                    {keyfile,"/etc/rabbitmq/ssl/key.pem"},
                    {verify,verify_peer},
                    {fail_if_no_peer_cert,true}]}
                 ]}
].
'

file { "/etc/rabbitmq/rabbitmq.config" :
   ensure => present,
   content => $RABBITMQ_CONFIG,
   require => Exec['copy-keys'],
   notify => Service['rabbitmq-server'],
}

exec { "create-vhost" :
     path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
     command => "rabbitmqctl add_vhost /sensu",
     unless => "rabbitmqctl list_vhosts | grep sensu",
     require => [ Exec['copy-keys'],Service['rabbitmq-server']],
}

exec { "add-sensu-user-in-rabbitmq" :
     path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
     command => "rabbitmqctl add_user sensu $RABBITMQ_PASSWD; rabbitmqctl set_permissions -p /sensu sensu '.*' '.*' '.*' ",
     require => Exec['create-vhost'],
     unless => "rabbitmqctl list_users | grep sensu",
}

# REDIS

package { "redis-server" :
 ensure => present,
}

service { "redis-server" :
  ensure => running,
  require => Package['redis-server'],
}


# SENSU
     exec { "add-sensu-repo-key" :
             path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
             command => "curl http://repositories.sensuapp.org/apt/pubkey.gpg | apt-key add - ",
             unless => "ls /etc/apt/sources.list.d/sensu.list",
             require => [Package['redis-server'],Exec['add-sensu-user-in-rabbitmq']],
     }

     exec { "add-sensu-repo" :
             path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
             command => "echo ' deb     http://repositories.sensuapp.org/apt sensu main' >> /etc/apt/sources.list.d/sensu.list ; apt-get update",
             require => Exec["add-sensu-repo-key"],
             unless => "ls /etc/apt/sources.list.d/sensu.list"
     }

    package { "sensu" :
      ensure => present,
      require => Exec['add-sensu-repo'],
      }

    file { "/etc/sensu/config.json" :
       ensure => present,
       content => $SENSU_CONFIG,
       require => Package['sensu'],
       notify => [ Service['sensu-server'],Service['sensu-api']]
    }

    file { "/etc/sensu/ssl" :
      ensure => directory,
      mode => 644,
      require => Package['sensu'],
     }

    exec { "copy-sensu-keys" :
     path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
     command => "cp /tmp/sensu_ssl_tool/client/cert.pem /etc/sensu/ssl/client_cert.pem; cp /tmp/sensu_ssl_tool/client/key.pem /etc/sensu/ssl/client_key.pem ",
     unless => "ls /etc/sensu/ssl/client_key.pem && ls /etc/sensu/ssl/client_cert.pem",
     require => File['/etc/sensu/ssl'],
     }

    service { "sensu-server" :
      ensure => running,
      require => Exec['copy-sensu-keys'],
    }

    service { "sensu-api" :
      ensure => running,
      require => Exec['copy-sensu-keys'],
    }

   file { "/etc/sensu/conf.d/client.json":
     ensure => present,
     content => $SENSU_CLIENT_CONFIG,
     require => Exec['copy-sensu-keys'],
     notify => Service['sensu-client'],
   }



    service { "sensu-client" :
      ensure => running,
      require => Exec['copy-sensu-keys'],
      }

    package { "uchiwa" :
      ensure => present,
      require => Package['sensu'],
    }

file { "/etc/sensu/uchiwa.json" :
   ensure => present,
   content => $UCHIWA_CONFIG,
   require => Package['uchiwa'],
   notify => Service['uchiwa'],
}


   service { "uchiwa" :
      ensure => running,
      require => File['/etc/sensu/uchiwa.json'],
      }
