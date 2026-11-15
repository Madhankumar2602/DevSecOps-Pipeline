# Manual integration checklist

Everything else is automated by Terraform, Ansible and the Jenkinsfile. **These are the only
things a person has to do by hand**, in this order. Each one involves either your accounts
(AWS, GitHub, email), a secret you shouldn't commit, or a web UI with no reliable API on first boot.
The full walkthrough for each step is in [README.md](README.md).

## A. Your laptop and accounts (once)

| # | Do this | Why it's manual |
|---|---|---|
| 1 | Install **WSL2 (Ubuntu)** on Windows, then Git, AWS CLI v2, **Terraform ≥ 1.10**, Ansible ≥ 2.15 inside it | Ansible doesn't run natively on Windows |
| 2 | `ssh-keygen -t ed25519 -f ~/.ssh/shipguard -N ""` | Your private key never leaves your laptop |
| 3 | Put AWS credentials in `~/.aws/credentials` (Learner Lab: *AWS Details → AWS CLI*; own account: `aws configure`). Own account: create a **$15 budget alert** | Your credentials |
| 4 | Create a **GitHub repo**, then in the `devsecops-pipeline/` folder: `git init`, commit, `git remote add origin …`, push to `main` | Your GitHub account. ⚠ Your home folder `C:\Users\madhan` is itself a git repo, so run `git init` **inside `devsecops-pipeline/`** so the project gets its own repo |

## B. Provisioning (once, run by you)

| # | Do this | Why it's manual |
|---|---|---|
| 5 | `cp terraform/terraform.tfvars.example terraform/terraform.tfvars` and fill in **`my_ip_cidr`** (`curl -s https://checkip.amazonaws.com` + `/32`), **`alert_email`**, `owner`, and keep or delete the 3 Learner Lab lines | Your IP and email. This file is git-ignored |
| 6 | `terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply`, then `terraform -chdir=bootstrap output -raw backend_hcl > backend.hcl` (run from `terraform/`) | Creates the S3 state bucket. It's run once, from your laptop, with your credentials |
| 7 | `terraform init -backend-config=backend.hcl && terraform plan -out tfplan && terraform apply tfplan` (**Learner Lab: add `-refresh=false` to `plan`**, because the lab blocks an S3 read the provider needs; see README Troubleshooting) | **Read the plan** before you apply it, because this spends money |
| 8 | **Click "Confirm subscription"** in the AWS SNS email | AWS requires a person to opt in. **Without this you get no alarm emails** |
| 9 | `cd ansible && ansible-galaxy collection install -r requirements.yml && ansible-playbook playbooks/site.yml`. **Copy the Jenkins password** it prints at the end | Uses your SSH key |

## C. SonarQube UI, `http://<jenkins-ip>:9000` (once)

| # | Do this |
|---|---|
| 10 | Log in `admin`/`admin` and **set a new password** |
| 11 | *My Account → Security → Generate token*, type **Global Analysis Token**, then copy it |
| 12 | **No webhook needed.** The scanner waits for the Quality Gate itself. Paste the token only into the Jenkins credential, never into chats or files |

## D. Jenkins UI, `http://<jenkins-ip>:8080` (once)

| # | Do this |
|---|---|
| 13 | Paste the initial admin password, choose **Install suggested plugins**, and create your admin user |
| 14 | *Manage Jenkins → Credentials → Global → Add*. Kind **Secret text**, ID **`sonar-token`** (exact), value = the token from step 11 |
| 15 | *Manage Jenkins → System → SonarQube servers*. Tick *Environment variables*, Name **`sonarqube`** (exact, matches the Jenkinsfile), URL `http://localhost:9000`, token `sonar-token` |
| 16 | *New Item → `shipguard` → Pipeline → Pipeline script from SCM*. Git URL = your repo, branch `*/main`, script path `Jenkinsfile`. **Private repo:** add a GitHub PAT as a *Username with password* credential and select it here |
| 17 | Click **Build Now** once. After that, Jenkins polls GitHub every 2 minutes, so every push builds automatically |

## E. Recurring / as needed

| When | Do this |
|---|---|
| Every **Learner Lab** session | *Start Lab*, then paste the new credentials into `~/.aws/credentials` (they expire after 4 h) |
| Your home **IP changes** | Update `my_ip_cidr`, then `terraform apply` (otherwise SSH, Jenkins and the app time out) |
| **Trivy blocks** a build on a new HIGH/CRITICAL CVE | Bump the base image or the dependency. Accept a risk only by adding the CVE to `security/.trivyignore` **with a reason and expiry date** |
| You're **done for the day** | Stop the instances (own account) or *End Lab* (Learner Lab) |
| Project **finished** | `terraform destroy`. The state bucket is kept on purpose (`prevent_destroy`); see README Step 12 to remove it too |

## Deliberately not automated

- **GitHub webhook → Jenkins.** The security group lets only your IP reach Jenkins, so GitHub
  can't call it. The Jenkinsfile polls instead (`pollSCM H/2`). To use webhooks, you'd need to
  open 8080 to GitHub's published hook IP ranges (`https://api.github.com/meta`).
- **Jenkins/SonarQube first-time setup (C, D).** This could be scripted with Jenkins
  Configuration-as-Code (JCasC) and the SonarQube web API, but that would mean storing admin
  passwords and tokens in Ansible. For a lab, a two-minute manual setup is safer and easier to explain.
- **Scanner image versions** use `:latest` (Jenkinsfile `environment {}`). Pin them to fixed
  versions once your pipeline is green, so a scanner update can't break a build overnight.

## Already automated (don't do these by hand)

VPC/subnet/route/flow logs · security groups · EC2 + Elastic IPs + IMDSv2 + encrypted disks ·
IAM roles (or Learner Lab `LabInstanceProfile`) · ECR · KMS · S3 report bucket and state bucket ·
CloudWatch log groups, alarms, dashboard · SNS topic · Ansible inventory and `/etc/shipguard/pipeline.env` ·
Docker, Java, Jenkins + plugins, Trivy, kubectl, SonarQube container, k3s, kubeconfig, ECR credential helper
and pull-secret cron · CloudWatch agent · every gate, ECR push, deploy by digest with auto-rollback,
smoke test, report upload to S3, and pipeline-health metrics + failure alarm.
