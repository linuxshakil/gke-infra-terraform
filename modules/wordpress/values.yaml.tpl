##
## WordPress
##

wordpressUsername: admin

wordpressEmail: admin@${domain}

wordpressBlogName: MyAhad Blog

##
## Database
##

mariadb:
  enabled: false

externalDatabase:
  host: ${db_host}
  user: ${db_user}
  database: ${db_name}
  existingSecret: wordpress-db
  existingSecretPasswordKey: password

##
## Persistence
##

persistence:
  enabled: true
  existingClaim: wordpress-data

##
## Service Account
##

serviceAccount:
  create: false
  name: wordpress-sa

##
## Service
##

service:
  type: ClusterIP

##
## Resources
##

resources:
  requests:
    cpu: 250m
    memory: 512Mi

  limits:
    cpu: 500m
    memory: 1Gi

##
## Health
##

startupProbe:
  enabled: true

livenessProbe:
  enabled: true

readinessProbe:
  enabled: true

##
## Security
##

podSecurityContext:
  enabled: true

containerSecurityContext:
  enabled: true
