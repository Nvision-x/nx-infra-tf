#!/bin/bash


kubectl delete pod -l app=api
kubectl delete pod -l app=api-tasks
kubectl delete pod -l app=alerts
kubectl delete pod -l app=alerts-api
kubectl delete pod -l app=cyclr-hooks
kubectl delete pod -l app=connector
kubectl delete pod -l app=enricher
kubectl delete pod -l app=archiver
kubectl delete pod -l app=sweeper
kubectl delete pod -l app=jobengine
kubectl delete pod -l app=migration
kubectl delete pod -l app=gracie
kubectl delete pod -l app=cron-run
kubectl delete pod -l app=watchdog
kubectl delete pod -l app=test-connection
kubectl delete pod -l io.kompose.service=nx-notify
kubectl delete pod -l io.kompose.service=nx-qcluster
kubectl delete pod -l io.kompose.service=nx-main
kubectl delete pod -l io.kompose.service=nx-nginx
