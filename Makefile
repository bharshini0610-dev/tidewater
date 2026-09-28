up:
	k3d cluster create settle
	kubectl apply -f deploy/k8s/
