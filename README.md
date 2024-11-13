# intership-loki
Loki implementation for backstage.

- #### The `src` directory contains all the code for each step of each pipeline.
    - #### `src/cnoe-loki-manifest-templates(bucketS3)`:
      Contains files stored in cnoe-loki-manifest-templates S3 bucket.
    - #### `src/control-plane` contains all steps of the control plane pipeline.
        - #### `src/control-plane/pull` contains code for the pull step of the control plane pipeline:
          This is a preliminary step whose objective is primarily to retrieve configurations and prepare the environment for the next steps.
          During this step, the following operations are performed:
            1) Configuration files are retrieved, including parameters related to the control plane, both those that can be updated and those set only during the first installation.
            2) A security perimeter is created to limit permissions only to those necessary to execute this and the following pipeline steps.
               To accomplish this, an IAM role is created on AWS-based LOKI instances, associating policies that enable the required permissions.
               A similar approach would be used with other cloud providers.
            3) The template file for creating or updating the control plane is retrieved. This template is written with an infrastructure-as-code solution. For AWS-based LOKI instances, it’s recommended to store these files in an S3 bucket, enabling file versioning and secure access management. Similar solutions exist with other cloud providers.
        - #### `src/control-plane/check` contains code for the check step of the control plane pipeline:
          This is one of the most important steps in the pipeline because it checks the correctness of configuration parameters and halts pipeline execution if there’s an error.
          The operations executed are:
            1) For AWS-based LOKI instances, the role created in the previous step is assumed to restrict permissions to the minimum required.
            2) The network configuration is verified, particularly in AWS-based instances where the existence of the VPC, subnet, and SecurityGroup is checked, along with whether the subnets belong to the indicated VPC.
            3) It’s checked whether the control plane already exists (indicating an update) or needs to be created. For AWS-based instances using CloudFormation as the infrastructure-as-code solution, the existence of the Stack is also verified. If the Stack exists but the control plane does not, an error is returned, and the pipeline terminates. If the Stack exists, the associated control plane should also exist.
            4) If an update is being performed, the parameters that can only be set during the first installation are checked.
            5) If an update is being performed, the compatibility of any new control plane version with the current data node and plugin versions is checked.
        - #### `src/control-plane/deploy` contains code for the deploy step of the control plane pipeline:
          This step creates the control plane. Since configuration correctness has already been verified, there’s sufficient assurance that errors will not occur.
          The operations executed are:
            1) For AWS-based LOKI instances, the role created in the pull step is assumed to restrict permissions to the minimum required.
            2) The template for creating or updating the control plane is compiled.
            3) The previously compiled template is executed, creating or updating the control plane. For AWS-based solutions, AWS will handle any failure cases.
        - #### `src/control-plane/post-deploy` contains code for the post-deploy step of the control plane pipeline:
          In this step, several auxiliary operations are performed, as listed below:
            1) For AWS-based LOKI instances, the role created in the pull step is assumed to restrict permissions to the minimum required.
            2) For AWS-based LOKI instances, the control plane is made private, meaning it’s only accessible from an instance within the VPC or through a VPN.
            3) The kubeconfig file, which is needed to configure `kubectl` to manage the cluster from the terminal, is saved to make it accessible to the user who will use the cluster.
        - #### `src/control-plane/test` contains code for the test step of the control plane pipeline:
          This final step verifies whether the cluster is free of issues after creation or updating, and if any are found, reports the error.
          The operations executed are:
            1) For AWS-based LOKI instances, the role created in the pull step is assumed to restrict permissions to the minimum required.
            2) It checks if an update is being performed and, consequently, if data nodes already exist.
            3) If an update is being performed, internal cluster connectivity is verified.
            4) If an update is being performed, the correct functioning of plugins is verified.
            5) If an update is being performed, the state of the pods running on the cluster is checked for consistency.
    - #### `src/data-plane` contains all steps of the data plane pipeline.
        - #### `src/data-plane/pull` contains code for the pull step of the data plane pipeline.
        - #### `src/data-plane/check` contains code for the check step of the data plane pipeline.
        - #### `src/data-plane/deploy` contains code for the deploy step of the data plane pipeline.
        - #### `src/data-plane/test` contains code for the test step of the data plane pipeline.
    - #### `src/infr-plane` contains all steps of the infrastructure plane pipeline.
        - #### `src/infr-plane/pull` contains code for the pull step of the infrastructure plane pipeline.
        - #### `src/infr-plane/customization` contains code for the customization step of the infrastructure plane pipeline.
        - #### `src/infr-plane/deploy` contains code for the deploy step of the infrastructure plane pipeline.
        - #### `src/infr-plane/test` contains code for the test step of the infrastructure plane pipeline.