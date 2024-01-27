import os
import boto3
import logging

DEFAULT_TAGS = os.environ.get("DEFAULT_TAGS")
print("DEFAULT_TAGS", DEFAULT_TAGS)

logger = logging.getLogger()
level = logging.getLevelName(os.environ.get("LOG_LEVEL", "INFO"))
print("Logging level -- ", level)
logger.setLevel(level)

ec2_resource = boto3.resource("ec2")
ec2_client = boto3.client("ec2")
    
def lambda_handler(event, context):
    """
        Function that starts and stops ec2 instances according to schedule and with specific tags<br/>
        :param event: Input event that contains action and tags parameters, where tags is a list of comma separates key/value tags<br/>
        :param context: Lambda context<br/>
        :return: nothing
    """
    logger.info(f"event -- {event}")

    tags = get_tags(event["tags"] if "tags" in event else DEFAULT_TAGS)
    logger.info(f"tags -- {tags}")

    instances = get_instances_by_tags(tags)

    if event["action"] == "start":
        stopped_instances_ids = get_instance_ids_by_state(instances, "stopped")
        if stopped_instances_ids:
            ec2_client.start_instances(InstanceIds=stopped_instances_ids)
            logger.info("Starting instances")
        else:
            logger.warning("No instances available for starting")
    elif event["action"] == "stop":
        running_instances_ids = get_instance_ids_by_state(instances, "running")
        if running_instances_ids:
            ec2_client.stop_instances(InstanceIds=running_instances_ids)
            logger.info("Stopping instances")
        else:
            logger.warning("No instances available for stopping")
    else:
        logger.warning("This action is not supported")


def get_tags(tags):
    """
        Method that splits comma separated tags and returns a formed tags filter<br/>
        :param tags: Comma separated string with the tags values<br/>
        :return: tags structure
    """
    final_tags = []
    split_tags = tags.split(",")
    for tag in split_tags:
        values = tag.split("=")
        final_tags.append({
            "Name": values[0],
            "Values": [values[1]]
        })
    return final_tags


def get_instances_by_tags(tags):
    """
        Method that filters all ec2 instances and return only the instances with specific tags<br/>
        :param tags: Filter structure with tag values<br/>
        :return: list of ec2 instances
    """
    response = ec2_resource.instances.filter(Filters=tags)
    logger.info(f"Response -- {response}")
    for instance in response:
        logger.info(f"Instance -- {instance} State -- {instance.state['Name']}")

    return response

def get_instance_ids_by_state(instances, state):
    """
        Function that filters ec2 instances according to the given state and returns the ids<br/>
        :param instances: List of ec2 instances<br/>
        :param state: The desired instance state e.g. running<br/>
        :return: List of instances ids
    """
    filtered_instances = filter(lambda instance: instance.state["Name"] == state, instances)
    instances_ids = list(map(lambda instance: instance.id, filtered_instances))
    logger.info(f"Instances ids -- {instances_ids}")
    return instances_ids