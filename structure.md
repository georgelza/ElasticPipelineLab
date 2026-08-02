## Project structure

Short layout of all the artefacts that make up our project/article.

```
.
├── .github/
│   └── workflows/
│       └── ci.yml          # CI Pipeline (Builds image, updates manifest), original for app1
│
├── blog-doc/
│   └── diagrams/
│
├── k8s/
│   └── deployment.yml      # Kubernetes manifests (Deployment & Service), original for app1
│
├── my-pipeline             # diagrams and screenshots
├── .gitignore
├── app.py                  # FastAPI Application source code
├── argocd-app.yml          # arcgocd-app pipeline configuration
├── BUILD.md                # Base Kubrnetes cluster buid
├── Dockerfile              # Docker recipe / app1
├── README.md               # Main README
├── requirements.txt        # Python dependencies
├── structure.md            # This file
└── vcluster.yml            # our vCluser Recipe for our multinode Kubernetes
```


### Scope Creep

Instructions and updated artefacts to add our app2 application to our ArgoCD pipeline

```
.
├── .github/
│   └── workflows/
│       └── ci.yml          # CI Pipeline (Builds image, updates manifest)
│
├── app2/
│   ├── app2.py            # FastAPI Application source code
│   ├── ci.yml             # CI Pipeline (Builds image, updates manifest), modified to include app2
│   ├── deployment.yml     # Kubernetes manifests (Deployment & Service), modified to include app2
│   ├── Dockerfile         # Docker recipe / app2
│   └── README.md          # README file describing how to add/deploy app2
│
├── backup/                # Our original files for app 1, 
│   ├── argocd-app.yml
│   ├── ci.yml
│   └── deployment.yml
│
├── blog-doc/
│   ├── Exploring K8S on vCluster, Deploying a GitOps Stack.docx  # Our Blog as a word document.
│   └── diagrams/           # Various diagrams
│
├── k8s/
│   └── deployment.yml      # Kubernetes manifests (Deployment & Service)
│
├── my-pipeline             # various screenshots
├── .gitignore
├── app.py                  # FastAPI Application source code, app1
├── argocd-app.yml          # Docker recipe, app1
├── BUILD.md                # Docker recipe
├── Dockerfile              # Docker recipe
├── README.md               # Docker recipe
├── requirements.txt        # Python dependencies
├── structure.md            # This file
└── vcluster.yml            # our vCluser Recipe for our multinode Kubernetes
```