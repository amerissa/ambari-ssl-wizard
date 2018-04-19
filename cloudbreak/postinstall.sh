#!/bin/bash
  export AMBARI_HOST=$(hostname -f)
  export username=admin
  export password=admin
  export CLUSTER_NAME=$(curl -u $username:$password -X GET http://$AMBARI_HOST:8080/api/v1/clusters |grep cluster_name|grep -Po ': "(.+)'|grep -Po '[a-zA-Z0-9\-_!?.]+')

cd ~/ambari-ssl-wizard/
./wizard.py


TASKID=$(curl -H "X-Requested-By:ambari" -u $username:$password -i -X PUT -d  '{"RequestInfo":{"context":"Stop Service"},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services | grep '"id" :' | cut -d : -f 2 | cut -d , -f 1 | sed 's/ //g')
  LOOPESCAPE="false"
  until [ "$LOOPESCAPE" == true ]; do
      TASKSTATUS=$(curl -s -u $username:$password -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
      if [ "$TASKSTATUS" == COMPLETED ]; then
          LOOPESCAPE="true"
      fi
      echo Stopping Cluster
      sleep 2
  done


  TASKID=$(curl -H "X-Requested-By:ambari" -u $username:$password -i -X PUT -d '{"ServiceInfo": {"state" : "STARTED"}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services | grep '"id" :' | cut -d : -f 2 | cut -d , -f 1 | sed 's/ //g')
  LOOPESCAPE="false"
  until [ "$LOOPESCAPE" == true ]; do
      TASKSTATUS=$(curl -s -u $username:$password -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
      if [ "$TASKSTATUS" == COMPLETED ] || [ "$TASKSTATUS" == FAILED ] ; then
          LOOPESCAPE="true"
      fi
      echo Starting Cluster
      sleep 2
  done
ambari-server restart
ambari-server restart
