pipeline {
    agent any

    environment {
        SONAR_TOKEN     = credentials('sonar-token')
        SONAR_HOST      = 'http://host.docker.internal:9000'
        DOCKERHUB_CREDS = credentials('dockerhub-credentials')
        KUBECONFIG_FILE = credentials('kubeconfig')
        IMAGE_NAME      = "${DOCKERHUB_CREDS_USR}/flask-devops-tp"
        IMAGE_TAG       = "${BUILD_NUMBER}"
        KUBECONFIG      = "${WORKSPACE}/kubeconfig"
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Cloning repository...'
                checkout scm
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements.txt
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    . venv/bin/activate
                    pytest tests/ \
                        --cov=app \
                        --cov-report=xml:coverage.xml \
                        --cov-report=term-missing \
                        -v
                '''
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh '''
                        . venv/bin/activate
                        sonar-scanner \
                            -Dsonar.projectKey=flask-devops-tp \
                            -Dsonar.sources=app \
                            -Dsonar.tests=tests \
                            -Dsonar.python.coverage.reportPaths=coverage.xml \
                            -Dsonar.python.version=3
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 2, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    docker build \
                        --provenance=false \
                        -t ${IMAGE_NAME}:${IMAGE_TAG} \
                        -t ${IMAGE_NAME}:latest \
                        .
                    echo "Image built: ${IMAGE_NAME}:${IMAGE_TAG}"
                '''
            }
        }

        stage('Trivy Scan') {
            steps {
                sh '''
                    trivy image \
                        --exit-code 1 \
                        --ignore-unfixed \
                        --severity HIGH,CRITICAL \
                        --no-progress \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
        }

        stage('Docker Push') {
            steps {
                sh '''
                    echo "${DOCKERHUB_CREDS_PSW}" | docker login \
                        -u "${DOCKERHUB_CREDS_USR}" --password-stdin
                    docker push ${IMAGE_NAME}:${IMAGE_TAG}
                    docker push ${IMAGE_NAME}:latest
                    echo "Pushed: ${IMAGE_NAME}:${IMAGE_TAG}"
                '''
            }
        }

        stage('Terraform — Provision Infrastructure') {
            steps {
                sh '''
                    cp ${KUBECONFIG_FILE} ${WORKSPACE}/kubeconfig
                    chmod 600 ${WORKSPACE}/kubeconfig
                    cd terraform/
                    terraform init -input=false
                    terraform apply -auto-approve -input=false
                '''
            }
        }

        stage('Ansible — Configure & Deploy') {
            steps {
                sh '''
                    cp ${KUBECONFIG_FILE} ${WORKSPACE}/kubeconfig
                    chmod 600 ${WORKSPACE}/kubeconfig

                    sed "s|DOCKER_IMAGE_PLACEHOLDER|${IMAGE_NAME}:${IMAGE_TAG}|g" \
                        k8s/deployment.yaml > /tmp/deployment-final.yaml
                    cp /tmp/deployment-final.yaml k8s/deployment.yaml

                    ansible-playbook ansible/playbook.yml
                '''
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    cp ${KUBECONFIG_FILE} ${WORKSPACE}/kubeconfig
                    chmod 600 ${WORKSPACE}/kubeconfig

                    echo "Waiting for pod to be ready..."
                    kubectl wait --for=condition=ready pod \
                        -l app=flask-app \
                        -n flask-app \
                        --timeout=120s

                    NODE_IP=$(kubectl get nodes \
                        -o jsonpath="{.items[0].status.addresses[0].address}")
                    echo "Node IP: ${NODE_IP}"

                    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                        http://${NODE_IP}:30080/health)

                    echo "HTTP response code: ${HTTP_CODE}"

                    if [ "${HTTP_CODE}" = "200" ]; then
                        echo "Smoke test PASSED — app is healthy"
                    else
                        echo "Smoke test FAILED — got HTTP ${HTTP_CODE}"
                        exit 1
                    fi
                '''
            }
        }
    }

    post {
        success {
            echo "Full pipeline passed! Image: ${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo 'Pipeline failed — check the logs above.'
        }
        always {
            sh 'docker logout || true'
        }
    }
}
