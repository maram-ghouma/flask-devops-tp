terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "kubernetes" {
  config_path = "/tmp/kubeconfig"
}

resource "kubernetes_namespace" "flask_app" {
  metadata {
    name = "flask-app"
    labels = {
      managed-by = "terraform"
    }
  }
}

resource "kubernetes_service_account" "flask_sa" {
  metadata {
    name      = "flask-sa"
    namespace = kubernetes_namespace.flask_app.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "flask_crb" {
  metadata {
    name = "flask-crb"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.flask_sa.metadata[0].name
    namespace = kubernetes_namespace.flask_app.metadata[0].name
  }
}
