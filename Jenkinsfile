// ShipGuard DevSecOps pipeline
// Gates: Gitleaks -> unit tests -> SonarQube -> tfsec/Checkov -> Trivy -> OWASP ZAP -> deploy to Kubernetes
// Any gate failing stops the pipeline; nothing reaches ECR or Kubernetes unless every gate is green.

pipeline {
  agent any

  options {
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
  }

  // GitHub can't reach Jenkins (SG allows only your IP), so poll for new commits.
  triggers { pollSCM('H/2 * * * *') }

  environment {
    REPORTS  = 'reports'
    DAST_NET = "dast-net-${BUILD_NUMBER}"
    DAST_APP = "shipguard-dast-${BUILD_NUMBER}"
    // Pin scanner versions here once you're happy with them
    GITLEAKS_IMG = 'zricethezav/gitleaks:latest'
    TFSEC_IMG    = 'aquasec/tfsec:latest'
    CHECKOV_IMG  = 'bridgecrew/checkov:latest'
    SCANNER_IMG  = 'sonarsource/sonar-scanner-cli:latest'
    ZAP_IMG      = 'ghcr.io/zaproxy/zaproxy:stable'
    NODE_IMG     = 'node:24-alpine'
  }

  stages {

    stage('Init') {
      steps {
        script {
          // Written by Ansible from Terraform outputs — no hard-coded account IDs or IPs here.
          // Plain Groovy KEY=VALUE parsing (no plugin needed).
          sh(script: 'cat /etc/shipguard/pipeline.env', returnStdout: true).readLines().each { line ->
            line = line.trim()
            if (line && !line.startsWith('#') && line.contains('=')) {
              def i = line.indexOf('=')
              env."${line.substring(0, i).trim()}" = line.substring(i + 1).trim()
            }
          }
          env.SHORT_SHA = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.SHORT_SHA}"
          env.IMAGE     = "${env.ECR_REPOSITORY_URL}:${env.IMAGE_TAG}"
          env.SONAR_QG  = 'NOT_RUN'
          env.BUILD_START_MS = "${currentBuild.startTimeInMillis}"
        }
        sh 'rm -rf "$REPORTS" && mkdir -p "$REPORTS" && chmod 777 "$REPORTS"'
        echo "Building ${env.IMAGE}"
      }
    }

    stage('Gate 0 · Secrets (Gitleaks)') {
      steps {
        sh '''
          docker run --rm -u "$(id -u):$(id -g)" -v "$WORKSPACE:/repo" "$GITLEAKS_IMG" \
            detect --source /repo --no-banner --redact \
            --report-format json --report-path /repo/reports/gitleaks.json --exit-code 1
        '''
      }
    }

    stage('Unit tests + dependency audit') {
      steps {
        sh '''
          docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
            -v "$WORKSPACE/app:/app" -w /app "$NODE_IMG" \
            sh -c "npm ci --no-audit --no-fund && npm test && npm audit --omit=dev --audit-level=critical"
        '''
      }
    }

    stage('Gate 1 · Code quality (SonarQube)') {
      steps {
        // The scanner itself waits for the Quality Gate (sonar.qualitygate.wait) and exits non-zero
        // if it fails, so no SonarQube -> Jenkins webhook is needed. (SonarQube blocks webhooks to
        // private IPs and to its own host, and here SonarQube and Jenkins share one server.)
        withSonarQubeEnv('sonarqube') {
          script {
            def rc = sh(returnStatus: true, script: '''
              docker run --rm --network host -u "$(id -u):$(id -g)" \
                -e SONAR_HOST_URL="$SONAR_HOST_URL" -e SONAR_TOKEN="$SONAR_AUTH_TOKEN" \
                -e SONAR_USER_HOME=/usr/src/.sonar \
                -v "$WORKSPACE/app:/usr/src" "$SCANNER_IMG" \
                -Dsonar.projectVersion="$IMAGE_TAG" \
                -Dsonar.qualitygate.wait=true -Dsonar.qualitygate.timeout=300
            ''')
            env.SONAR_QG = (rc == 0) ? 'OK' : 'ERROR'
            if (rc != 0) {
              error 'SonarQube Quality Gate failed (or the analysis failed). See the scanner output above and the ShipGuard project in SonarQube.'
            }
          }
        }
      }
    }

    stage('Gate 2 · Infrastructure as Code') {
      parallel {
        stage('tfsec') {
          steps {
            sh '''
              # JSON report of everything (never fails) ...
              docker run --rm -u "$(id -u):$(id -g)" -v "$WORKSPACE:/src" "$TFSEC_IMG" /src/terraform \
                --no-color --soft-fail --format json --out /src/reports/tfsec.json
              # ... then the gate: any HIGH or CRITICAL fails the build (main stack + state bootstrap)
              for dir in terraform terraform/bootstrap; do
                docker run --rm -u "$(id -u):$(id -g)" -v "$WORKSPACE:/src" "$TFSEC_IMG" "/src/$dir" \
                  --no-color --minimum-severity HIGH
              done
            '''
          }
        }
        stage('Checkov') {
          steps {
            sh '''
              docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$WORKSPACE:/src" "$CHECKOV_IMG" \
                -d /src/terraform -d /src/k8s --framework terraform kubernetes \
                --skip-download --compact --quiet \
                -o cli -o json --output-file-path console,/src/reports
            '''
          }
        }
      }
    }

    stage('Build image') {
      steps {
        sh '''
          docker build --pull \
            --label org.opencontainers.image.revision="$GIT_COMMIT" \
            --label org.opencontainers.image.version="$IMAGE_TAG" \
            -t "$IMAGE" app
        '''
      }
    }

    stage('Gate 3 · Container (Trivy)') {
      steps {
        sh '''
          trivy image --quiet --scanners vuln --format json --output "$REPORTS/trivy-image.json" "$IMAGE"
          # The gate: any HIGH or CRITICAL CVE that has a fix available fails the build
          trivy image --quiet --skip-db-update --severity HIGH,CRITICAL --ignore-unfixed \
            --ignorefile security/.trivyignore --exit-code 1 "$IMAGE"
        '''
      }
    }

    stage('Gate 4 · Runtime (OWASP ZAP)') {
      steps {
        sh '''
          docker network create "$DAST_NET"
          docker run -d --name "$DAST_APP" --network "$DAST_NET" --read-only --tmpfs /tmp "$IMAGE"
          for i in $(seq 1 30); do
            docker exec "$DAST_APP" wget -qO- http://127.0.0.1:3000/healthz && break
            sleep 2
          done

          cp security/zap-baseline.conf "$REPORTS/"
          set +e
          docker run --rm --network "$DAST_NET" -v "$WORKSPACE/$REPORTS:/zap/wrk:rw" "$ZAP_IMG" \
            zap-baseline.py -t "http://$DAST_APP:3000" -c zap-baseline.conf \
            -J zap.json -r zap.html -w zap.md -m 2
          rc=$?
          set -e
          # 0 = clean, 2 = warnings only, 1 = a FAIL rule triggered, 3 = scanner error
          if [ "$rc" -eq 1 ] || [ "$rc" -eq 3 ]; then
            echo "ZAP gate failed (exit $rc)"; exit 1
          fi
          python3 scripts/scan_summary.py --reports "$REPORTS" --gate zap
        '''
      }
      post {
        always {
          sh 'docker rm -f "$DAST_APP" >/dev/null 2>&1 || true; docker network rm "$DAST_NET" >/dev/null 2>&1 || true'
        }
      }
    }

    stage('Push to Amazon ECR') {
      steps {
        // Docker uses amazon-ecr-credential-helper + the EC2 instance role: no stored AWS keys.
        sh 'docker push "$IMAGE"'
        script {
          env.IMAGE_DIGEST_REF = sh(script: 'docker inspect --format "{{index .RepoDigests 0}}" "$IMAGE"', returnStdout: true).trim()
        }
        echo "Pushed ${env.IMAGE_DIGEST_REF}"
      }
    }

    stage('Deploy to Kubernetes') {
      steps {
        sh '''
          python3 scripts/scan_summary.py --reports "$REPORTS" --build "$BUILD_NUMBER" \
            --commit "$GIT_COMMIT" --sonar "$SONAR_QG" --out "$REPORTS/scan-summary.json"
          bash scripts/deploy.sh
        '''
      }
    }

    stage('Smoke test') {
      steps {
        sh 'bash scripts/smoke_test.sh'
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
      publishHTML(target: [reportDir: 'reports', reportFiles: 'zap.html', reportName: 'OWASP ZAP report',
                           allowMissing: true, keepAll: true, alwaysLinkToLastBuild: true])
      sh '''
        if [ -n "${REPORTS_BUCKET:-}" ]; then
          aws s3 cp "$REPORTS" "s3://$REPORTS_BUCKET/builds/$BUILD_NUMBER/" --recursive --only-show-errors || true
        fi
        docker rmi "$IMAGE" >/dev/null 2>&1 || true
      '''
    }
    success {
      sh 'bash scripts/pipeline_metric.sh 0'
      echo "All gates passed — ${env.IMAGE_DIGEST_REF} is live at http://${env.K8S_PUBLIC_IP}:30080"
    }
    failure {
      // BuildFailed=1 triggers the "<project>-pipeline-failed" CloudWatch alarm -> SNS email
      sh 'bash scripts/pipeline_metric.sh 1'
      echo 'A security gate or deployment step failed. Nothing new was deployed. Check the stage logs and reports/.'
    }
  }
}
