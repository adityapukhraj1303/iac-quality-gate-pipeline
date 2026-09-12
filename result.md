# Deployment Result

This project successfully deploys the monitoring stack and app workloads on a working EKS cluster. The Grafana dashboard shows live CPU and memory performance for the production-ready DevOps pipeline setup.

![Grafana monitoring dashboard](docs/images/grafana-dashboard-result.svg)

## Outcome

- EKS cluster is healthy and ready
- Prometheus and Grafana are running via the kube-prometheus-stack
- Kubernetes workloads are active and reporting telemetry
- The pipeline is ready for final verification and continued CI/CD automation

## Related docs

- [README.md](README.md)
- [README-FINAL-SETUP.md](README-FINAL-SETUP.md)

## Useful commands

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pods -n monitoring
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Then open: http://localhost:3000
