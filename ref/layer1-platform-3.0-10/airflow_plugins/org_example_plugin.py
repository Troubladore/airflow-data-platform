from airflow.plugins_manager import AirflowPlugin
class OrgExamplePlugin(AirflowPlugin):
    name = "org_example"
    hooks = []
    operators = []
    macros = []
    flask_blueprints = []
